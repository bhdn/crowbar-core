#
# Copyright (c) 2011 Dell Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Note : This script runs on both the admin and compute nodes.
# It intentionally ignores the bios->enable node data flag.

return if node[:platform_family] == "windows"

bmc_net = Barclamp::Inventory.get_network_by_type(node, "bmc")
admin_net = Barclamp::Inventory.get_network_by_type(node, "admin")

return if bmc_net.nil? || admin_net.nil?

nat_node = search(:node, "roles:bmc-nat-router").first rescue return
return if nat_node.nil?
nat_admin_net = Barclamp::Inventory.get_network_by_type(nat_node, "admin")

return if admin_net.subnet == bmc_net.subnet && admin_net.netmask == bmc_net.netmask

bmc_cidr = IP::IP4.netmask_to_subnet(bmc_net.netmask)

bash "Add route to get to our BMC via nat" do
  code "ip route add #{bmc_net.subnet}/#{bmc_cidr} via #{nat_admin_net.address}"
  not_if "ip route show via #{nat_admin_net.address} | grep -q #{bmc_net.subnet}/#{bmc_cidr}"
end
