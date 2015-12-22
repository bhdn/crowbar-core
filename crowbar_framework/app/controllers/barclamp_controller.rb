#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef"
require "json"

class BarclampController < ApplicationController
  skip_before_filter :enforce_installer, if: proc { Crowbar::Installer.initial_chef_client? }
  before_filter :initialize_service
  before_filter :controller_to_barclamp

  def controller_to_barclamp
    @bc_name = params[:barclamp] || params[:controller]
    @service_object.bc_name = @bc_name
  end

  self.help_contents = Array.new(superclass.help_contents)

  #
  # Barclamp List (generic)
  #
  # Provides the restful api call for
  # List Barclamps 	/crowbar 	GET 	Returns a json list of string names for barclamps
  #
  add_help(:barclamp_index)
  def barclamp_index
    @barclamps = ServiceObject.all
    respond_to do |format|
      format.html { raise ActionController::RoutingError.new("Not Found") }
      format.xml  { render xml: @barclamps }
      format.json { render json: @barclamps }
    end
  end

  #
  # Provides the restful api call for
  # List Versions 	/crowbar/<barclamp-name> 	GET 	Returns a json list of string names for the versions
  #
  add_help(:versions)
  def versions
    ret = @service_object.versions
    return render text: ret[1], status: ret[0] if ret[0] != 200
    render json: ret[1]
  end

  #
  # Provides the restful api call for
  # Transition 	/crowbar/<barclamp-name>/<version>/transition/<barclamp-instance-name> 	POST 	Informs the barclamp instance of a change of state in the specified node
  # Transition 	/crowbar/<barclamp-name>/<version>/transition/<barclamp-instance-name>?state=<state>&name=<hostname> 	GET 	Informs the barclamp instance of a change of state in the specified node - The get is supported here to allow for the limited function environment of the installation system.
  #
  add_help(:transition, [:id, :name, :state], [:get,:post])
  def transition
    id = params[:id]       # Provisioner id
    state = params[:state] # State of node transitioning
    name = params[:name] # Name of node transitioning

    unless valid_transition_states.include?(state)
      render text: "State '#{state}' is not valid.", status: 400
    else
      status, response = @service_object.transition(id, name, state)
      if status != 200
        render text: response, status: status
      else
        # Be backward compatible with barclamps returning a node hash, passing
        # them intact.
        if response[:name]
          render json: NodeObject.find_node_by_name(response[:name]).to_hash
        else
          render json: response
        end
      end
    end
  end

  #
  # Provides the restful api call for
  # Show Instance 	/crowbar/<barclamp-name>/<version>/<barclamp-instance-name> 	GET 	Returns a json document describing the instance
  #
  add_help(:show,[:id])
  def show
    ret = @service_object.show_active params[:id]
    @role = ret[1]
    Rails.logger.debug "Role #{ret.inspect}"
    respond_to do |format|
      format.html {
        return redirect_to proposal_barclamp_path controller: @bc_name, id: params[:id] if ret[0] != 200
        render template: "barclamp/show"
      }
      format.xml  {
        return render text: @role, status: ret[0] if ret[0] != 200
        render xml: ServiceObject.role_to_proposal(@role, @bc_name)
      }
      format.json {
        return render text: @role, status: ret[0] if ret[0] != 200
        render json: ServiceObject.role_to_proposal(@role, @bc_name)
      }
    end
  end

  #
  # Provides the restful api call for
  # Destroy Instance 	/crowbar/<barclamp-name>/<version>/<barclamp-instance-name> 	DELETE 	Delete will deactivate and remove the instance
  #
  add_help(:delete,[:id],[:delete])
  def delete
    params[:id] = params[:id] || params[:name]
    ret = [500, "Server Problem"]
    begin
      ret = @service_object.destroy_active(params[:id])
      set_flash(ret, "proposal.actions.delete_%s")
    rescue StandardError => e
      Rails.logger.error "Failed to deactivate proposal: #{e.message}\n#{e.backtrace.join("\n")}"
      flash[:alert] = t("proposal.actions.delete_failure") + e.message
      ret = [500, flash[:alert]]
    end

    respond_to do |format|
      format.html {
        redirect_to barclamp_modules_path(id: @bc_name)
      }
      format.xml  {
        return render text: ret[1], status: ret[0] if ret[0] != 200
        render xml: {}
      }
      format.json {
        return render text: ret[1], status: ret[0] if ret[0] != 200
        render json: {}
      }
    end
  end

  #
  # Provides the restful api call for
  # List Elements 	/crowbar/<barclamp-name>/<version>/elements 	GET 	Returns a json list of roles that a node could be assigned to
  #
  add_help(:elements)
  def elements
    ret = @service_object.elements
    return render text: ret[1], status: ret[0] if ret[0] != 200
    render json: ret[1]
  end

  #
  # Provides the restful api call for
  # List Nodes Available for Element 	/crowbar/<barclamp-name>/<version>/elements/<barclamp-instance-name> 	GET 	Returns a json list of nodes that can be assigned to that element
  #
  add_help(:element_info,[:id])
  def element_info
    ret = @service_object.element_info(params[:id])
    return render text: ret[1], status: ret[0] if ret[0] != 200
    render json: ret[1]
  end

  #
  # Provides the restful api call for
  # List Instances 	/crowbar/<barclamp-name>/<version> 	GET 	Returns a json list of string names for the ids of instances
  #
  add_help(:index)
  def index
    respond_to do |format|
      format.html {
        @title ||= "#{@bc_name.titlecase} #{t('barclamp.index.members')}"
        @count = -1
        members = {}
        list = BarclampCatalog.members(@bc_name)
        barclamps = BarclampCatalog.barclamps
        i = 0
        (list || {}).each { |bc, order| members[bc] = { "description" => barclamps[bc]["description"], "order"=>order || 99999} if !barclamps[bc].nil? and barclamps[bc]["user_managed"] }
        @modules = get_proposals_from_barclamps(members).sort_by { |k,v| "%05d%s" % [v[:order], k] }
        render "barclamp/index"
      }
      format.xml  {
        ret = @service_object.list_active
        @roles = ret[1]
        return render text: @roles, status: ret[0] if ret[0] != 200
        render xml: @roles
      }
      format.json {
        ret = @service_object.list_active
        @roles = ret[1]
        return render text: @roles, status: ret[0] if ret[0] != 200
        render json: @roles
      }
    end
  end

  #
  # Currently, A UI ONLY METHOD
  #
  add_help(:modules)
  def modules
    @title = I18n.t("barclamp.modules.title")
    @count = 0
    barclamps = BarclampCatalog.barclamps.dup.delete_if { |bc, props| !props["user_managed"] }
    @modules = get_proposals_from_barclamps(barclamps).sort_by { |k,v| "%05d%s" % [v[:order], k] }
    respond_to do |format|
      format.html { render "index" }
      format.xml  { render xml: @modules }
      format.json { render json: @modules }
    end
  end

  #
  # Currently, A UI ONLY METHOD
  #
  def get_proposals_from_barclamps(barclamps)
    modules = {}
    active = RoleObject.active
    barclamps.each do |name, details|
      modules[name] = { description: details["description"] || t("not_set"), order: details["order"], proposals: {}, expand: false, members: (details["members"].nil? ? 0 : details["members"].length) }

      bc_service = ServiceObject.get_service(name)
      modules[name][:allow_multiple_proposals] = bc_service.allow_multiple_proposals?
      suggested_proposal_name = bc_service.suggested_proposal_name

      Proposal.where(barclamp: name).each do |prop|
        # active is ALWAYS true if there is a role and or status maybe true if the status is ready, unready, or pending.
        status = (["unready", "pending"].include?(prop.status) or active.include?("#{name}_#{prop.name}"))
        @count += 1 unless @count<0  #allows caller to skip incrementing by initializing to -1
        modules[name][:proposals][prop.name] = {id: prop.id, description: prop.description, status: (status ? prop.status : "hold"), active: status}
        if prop.status === "failed"
          modules[name][:proposals][prop.name][:message] = prop.fail_reason
          modules[name][:expand] = true
        end
      end

      # find a free proposal name for what would be the next proposal
      modules[name][:suggested_proposal_name] = suggested_proposal_name
      (1..20).each do |x|
        possible_name = "#{suggested_proposal_name}_#{x}"
        next if active.include?("#{name}_#{possible_name}")
        next if modules[name][:proposals].keys.include?(possible_name)
        modules[name][:suggested_proposal_name] = possible_name
        break
      end if modules[name][:allow_multiple_proposals]
    end
    modules
  end

  #
  # List proposals
  # Return a list of available proposals
  # GET /crowbar/<barclamp-name>/<version>/proposals
  #
  add_help(:proposals, [], [:get])
  def proposals
    code, message = @service_object.proposals

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message
        end
        format.html do
          @proposals = message.map do |proposal|
            Proposal.where(barclamp: @bc_name, name: proposal).first
          end
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
        format.html do
          flash[:alert] = message

          redirect_to(
            root_url
          )
        end
      end
    end
  end

  #
  # Template proposal
  # Return the content of a proposal template
  # GET /crowbar/<barclamp-name>/<version>/proposals/template
  #
  add_help(:proposal_template, [], [:get])
  def proposal_template
    code, message = @service_object.proposal_template

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  #
  # Show proposal
  # Return the details of a specific proposal
  # GET /crowbar/<barclamp-name>/<version>/proposals/<barclamp-instance-name>
  #
  add_help(:proposal_show, [:id], [:get])
  def proposal_show
    code, message = @service_object.proposal_show(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message.raw_data
        end
        format.html do
          @proposal = message

          @active = begin
            RoleObject.active(
              params[:controller],
              params[:id]
            ).length > 0
          rescue
            false
          end

          flash.now[:alert] = @proposal.fail_reason if @proposal.failed?
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
        format.html do
          flash[:alert] = message

          redirect_to(
            root_url
          )
        end
      end
    end
  end

  #
  # Delete proposal
  # Remove a specific proposal
  # DELETE /crowbar/<barclamp-name>/<version>/proposals/<barclamp-instance-name>
  #
  add_help(:proposal_delete, [:id], [:delete])
  def proposal_delete
    code, message = @service_object.proposal_delete(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            barclamp_modules_path(
              id: params[:controller]
            )
          )
        end
        format.json do
          head :ok
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            barclamp_modules_path(
              id: params[:controller]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  #
  # Commit proposal
  # Commit a specific proposal to apply it
  # POST /crowbar/<barclamp-name>/<version>/proposals/commit/<barclamp-instance-name>
  #
  add_help(:proposal_commit, [:id], [:post])
  def proposal_commit
    code, message = @service_object.proposal_commit(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            proposal_barclamp_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :ok
        end
      when 202
        format.html do
          flash[:warning] = message

          redirect_to(
            proposal_barclamp_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :accepted
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            proposal_barclamp_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  #
  # Dequeue proposal
  # Remove a specific proposal from the queue
  # DELETE /crowbar/<barclamp-name>/<version>/proposals/dequeue/<barclamp-instance-name>
  #
  add_help(:proposal_dequeue, [:id], [:delete])
  def proposal_dequeue
    code, message = @service_object.dequeue_proposal(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            proposal_barclamp_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :ok
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            proposal_barclamp_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  #
  # Edit proposal
  # Update a specific proposal
  # POST /crowbar/<barclamp-name>/<version>/propsosals/<barclamp-instance-name>
  #
  add_help(:proposal_update, [:id], [:post])
  def proposal_update
    if params[:submit].nil?
      #
      # This is RESTFul path
      #

      code, message = @service_object.proposal_edit(
        params.slice(
          :id,
          :description,
          :attributes,
          :deployment,
          "crowbar-deep-merge-template"
        )
      )

      respond_to do |format|
        case code
        when 200
          format.html do
            redirect_to(
              proposal_barclamp_path(
                controller: params[:controller],
                id: params[:id]
              )
            )
          end
          format.json do
            render json: message
          end
        else
          format.html do
            flash[:alert] = message

            redirect_to(
              proposal_barclamp_path(
                controller: params[:controller],
                id: params[:id]
              )
            )
          end
          format.json do
            render json: { error: message }, status: code
          end
        end
      end
    else
      #
      # This is the UI path
      #

      if params[:submit] == t("barclamp.proposal_show.save_proposal")
        @proposal = Proposal.where(barclamp: params[:barclamp], name: params[:id] || params[:name]).first

        begin
          @proposal["attributes"][params[:barclamp]] = JSON.parse(params[:proposal_attributes])
          @proposal["deployment"][params[:barclamp]] = JSON.parse(params[:proposal_deployment])
          @service_object.save_proposal!(@proposal)
          flash[:notice] = t("barclamp.proposal_show.save_proposal_success")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      elsif params[:submit] == t("barclamp.proposal_show.commit_proposal")
        @proposal = Proposal.where(barclamp: params[:barclamp], name: params[:id] || params[:name]).first

        begin
          @proposal["attributes"][params[:barclamp]] = JSON.parse(params[:proposal_attributes])
          @proposal["deployment"][params[:barclamp]] = JSON.parse(params[:proposal_deployment])
          @service_object.save_proposal!(@proposal)
          answer = @service_object.proposal_commit(params[:name])
          flash[:alert] = answer[1] if answer[0] >= 400
          flash[:notice] = answer[1] if answer[0] >= 300 and answer[0] < 400
          flash[:notice] = t("barclamp.proposal_show.commit_proposal_success") if answer[0] == 200
          if answer[0] == 202
            missing_nodes = answer[1].map { |node_dns| NodeObject.find_node_by_name(node_dns) }

            unready_nodes = missing_nodes.select { |n| n.state != "ready" }.map(&:alias)
            unallocated_nodes = missing_nodes.reject(&:allocated?).map(&:alias)

            unless unready_nodes.empty?
              flash[:notice] = t(
                "barclamp.proposal_show.commit_proposal_queued",
                nodes: (unready_nodes - unallocated_nodes).join(", ")
              )
            end
            unless unallocated_nodes.empty?
              flash[:alert] = t(
                "barclamp.proposal_show.commit_proposal_queued_unallocated",
                nodes: unallocated_nodes.join(", ")
              )
            end
            if unready_nodes.empty? && unallocated_nodes.empty?
              # find out which proposals were not applied yet
              deps = @service_object.proposal_dependencies(
                ServiceObject.proposal_to_role(@proposal, params[:barclamp])
              )
              missing_barclamps = deps.map do |dep|
                prop = Proposal.where(barclamp: dep["barclamp"], name: dep["inst"]).first
                queued   = prop["deployment"][dep["barclamp"]]["crowbar-queued"] rescue false
                deployed = (prop["deployment"][dep["barclamp"]]["crowbar-status"] == "success") rescue false
                dep["barclamp"] if queued || !deployed
              end.compact
              flash[:notice] = t(
                "barclamp.proposal_show.commit_proposal_queued_dependency",
                barclamps: missing_barclamps.join(", ")
              )
            end
          end
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      elsif params[:submit] == t("barclamp.proposal_show.delete_proposal")
        begin
          answer = @service_object.proposal_delete(params[:name])
          set_flash(answer, "barclamp.proposal_show.delete_proposal_%s")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
        redirect_to barclamp_modules_path(id: (params[:barclamp] || ""))
        return
      elsif params[:submit] == t("barclamp.proposal_show.destroy_active")
        begin
          answer = @service_object.destroy_active(params[:name])
          set_flash(answer, "barclamp.proposal_show.destroy_active_%s")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      elsif params[:submit] == t("barclamp.proposal_show.dequeue_proposal")
        begin
          answer = @service_object.dequeue_proposal(params[:name])
          set_flash(answer, "barclamp.proposal_show.dequeue_proposal_%s")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      else
        Rails.logger.warn "Invalid action #{params[:submit]} for #{params[:id]}"
        flash[:alert] = "Invalid action #{params[:submit]}"
      end

      if params[:origin] && params[:origin] == "deployment_queue"
        redirect_to deployment_queue_path
      else
        redirect_params = {
          controller: params[:barclamp],
          id: params[:name]
        }

        redirect_params[:dep_raw] = true if view_context.show_raw_deployment?
        redirect_params[:attr_raw] = true if view_context.show_raw_attributes?

        redirect_to proposal_barclamp_path(redirect_params)
      end
    end
  end

  #
  # Create proposal
  # Create a new specific proposal
  # PUT /crowbar/<barclamp-name>/<version>/proposals
  #
  add_help(:proposal_create, [:name], [:put])
  def proposal_create
    params[:id] = params[:id] || params[:name]

    code, message = @service_object.proposal_create(
      params.slice(
        :id,
        :description,
        :attributes,
        :deployment,
        "crowbar-deep-merge-template"
      )
    )

    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message
        end
        format.html do
          redirect_to(
            proposal_barclamp_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
        format.html do
          flash[:alert] = message

          redirect_to(
            barclamp_modules_path(
              id: params[:controller]
            )
          )
        end
      end
    end
  end

  #
  # Currently, A UI ONLY METHOD
  #
  add_help(:proposal_status, [:id, :barclamp, :name], [:get])
  def proposal_status
    proposals = {}
    i18n = {}

    begin
      active = RoleObject.active(
        params[:barclamp],
        params[:name]
      )

      result = if params[:id].nil?
        Proposal.all
      else
        [
          Proposal.where(
            barclamp: params[:barclamp],
            name: params[:name]
          ).first
        ]
      end

      result.each do |prop|
        prop_id = "#{prop.barclamp}_#{prop.name}"
        status = (["unready", "pending"].include?(prop.status) || active.include?(prop_id))
        proposals[prop_id] = (status ? prop.status : "hold")

        i18n[prop_id] = {
          proposal: prop.name.humanize,
          status: t(
            "proposal.status.#{proposals[prop_id]}",
            default: proposals[prop_id]
          )
        }
      end

      render inline: {
        proposals: proposals,
        i18n: i18n,
        count: proposals.length
      }.to_json, cache: false
    rescue StandardError => e
      count = (e.class.to_s == "Errno::ECONNREFUSED" ? -2 : -1)
      lines = ["Failed to iterate over proposal list due to '#{e.message}'"] + e.backtrace
      Rails.logger.fatal(lines.join("\n"))

      render inline: {
        proposals: proposals,
        count: count,
        error: e.message
      }.to_json, cache: false
    end
  end

  add_help(:nodes, [], [:get])
  def nodes
    #Empty method to override if your barclamp has a "nodes" view.
  end

  private
  def set_flash(answer, common, success="success", failure="failure")
    if answer[0] == 200
      flash[:notice] = t(common % success)
    else
      flash[:alert] = t(common % failure)
      flash[:alert] += ": " + answer[1].to_s unless answer[1].to_s.empty?
    end
  end

  def valid_transition_states
    [
      "applying", "discovered", "discovering", "hardware-installed",
      "hardware-installing", "hardware-updated", "hardware-updating",
      "installed", "installing", "ready", "readying", "recovering",
      # used by sledgehammer / crowbar_join
      "debug", "problem", "reboot", "shutdown"
    ]
  end

  protected

  def initialize_service
    @service_object = ServiceObject.new logger
  end
end
