require "active_record"
require "active_resource"


class RemoteTenant < ActiveResource::Base
  self.site                 = "http://example.com/api/"
  self.element_name         = "account"
  self.format               = :json
  self.include_root_in_json = false
  self.user                 = "username"
  self.password             = "password"
end



class Tenant < ActiveRecord::Base
  remote_model RemoteTenant
  attr_remote :slug, :church_name => :name, :id => :remote_id
  fetch_with :name, :path => "by_nombre/:name"
  fetch_with :slug
end

class RemoteWithoutKey < ActiveRecord::Base
  self.table_name = "tenants"

  remote_model RemoteTenant
  attr_remote :id => :remote_id
end

class RemoteWithKey < ActiveRecord::Base
  self.table_name = "tenants"

  remote_model RemoteTenant
  attr_remote :slug, :church_name => :name
  remote_key :slug
end

class RemoteWithCompositeKey < ActiveRecord::Base
  self.table_name = "tenants"

  remote_model RemoteTenant
  attr_remote :group_id, :slug
  remote_key [:group_id, :slug], :path => "groups/:group_id/tenants/:slug"
end
