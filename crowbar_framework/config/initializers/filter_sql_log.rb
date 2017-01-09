#
# Copyright 2016, SUSE Linux GmbH
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

# filter sensitive data from our proposal table
module ActiveRecord
  class LogSubscriber
    alias :old_sql :sql

    def sql(event)
      if event.payload[:sql] =~ /^(INSERT INTO|UPDATE) "proposals".*/
        Rails.logger.debug(
          "SQL: INSERT/UPDATE transaction: filtering query to not expose potentially sensitive data"
        )
      else
        old_sql(event)
      end
    end
  end
end