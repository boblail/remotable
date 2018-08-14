require "test_helper"
require "remotable"
require "support/active_resource"
require "support/concurrently"
require "active_resource_simulator"
require "rr"


class ActiveResourceTest < ActiveSupport::TestCase
  include RR::Adapters::TestUnit

  test "should make an absolute path and add the format" do
    assert_equal "/api/accounts/by_slug/value.json",   RemoteTenant.expanded_path_for("by_slug/value")
  end




  # ========================================================================= #
  #  Finding                                                                  #
  # ========================================================================= #

  test "should be able to find resources by different attributes" do
    new_tenant_slug = "not_found"

    assert_equal 0, Tenant.where(:slug => new_tenant_slug).count,
      "There's not supposed to be a Tenant with the slug #{new_tenant_slug}."

    assert_difference "Tenant.count", +1 do
      RemoteTenant.run_simulation do |s|
        s.show(nil, {
          :id => 46,
          :slug => new_tenant_slug,
          :church_name => "Not Found"
        }, :path => "/api/accounts/by_slug/#{new_tenant_slug}.json")

        new_tenant = Tenant.find_by_slug(new_tenant_slug)
        assert_not_nil new_tenant, "A remote tenant was not found with the slug #{new_tenant_slug.inspect}"
      end
    end
  end

  test "should be able to find resources with a composite key" do
    group_id = 5
    slug = "not_found"

    assert_equal 0, RemoteWithCompositeKey.where(:group_id => group_id, :slug => slug).count,
      "There's not supposed to be a Tenant with the group_id #{group_id} and the slug #{slug}."

    assert_difference "RemoteWithCompositeKey.count", +1 do
      RemoteTenant.run_simulation do |s|
        s.show(nil, {
          :id => 46,
          :group_id => group_id,
          :slug => slug,
          :church_name => "Not Found"
        }, :path => "/api/accounts/groups/#{group_id}/tenants/#{slug}.json")

        new_tenant = RemoteWithCompositeKey.find_by_group_id_and_slug(group_id, slug)
        assert_not_nil new_tenant, "A remote tenant was not found with the group_id #{group_id} and the slug #{slug}."
      end
    end
  end

  test "should be able to find resources with the bang method" do
    new_tenant_slug = "not_found2"

    assert_equal 0, Tenant.where(:slug => new_tenant_slug).count,
      "There's not supposed to be a Tenant with the slug #{new_tenant_slug}."

    assert_difference "Tenant.count", +1 do
      RemoteTenant.run_simulation do |s|
        s.show(nil, {
          :id => 46,
          :slug => new_tenant_slug,
          :church_name => "Not Found"
        }, :path => "/api/accounts/by_slug/#{new_tenant_slug}.json")

        new_tenant = Tenant.find_by_slug!(new_tenant_slug)
        assert_not_nil new_tenant, "A remote tenant was not found with the slug #{new_tenant_slug.inspect}"
      end
    end
  end

  test "if a resource is neither local nor remote, raise an exception with the bang method" do
    new_tenant_slug = "not_found3"

    assert_equal 0, Tenant.where(:slug => new_tenant_slug).count,
      "There's not supposed to be a Tenant with the slug #{new_tenant_slug}."

    RemoteTenant.run_simulation do |s|
      s.show(nil, nil, :status => 404, :path => "/api/accounts/by_slug/#{new_tenant_slug}.json")

      assert_raises ActiveRecord::RecordNotFound do
        Tenant.find_by_slug!(new_tenant_slug)
      end
    end
  end

  test "should be able to find resources by different attributes and specify a path" do
    new_tenant_name = "JohnnyG"

    assert_equal 0, Tenant.where(:name => new_tenant_name).count,
      "There's not supposed to be a Tenant with the name #{new_tenant_name}."

    assert_difference "Tenant.count", +1 do
      RemoteTenant.run_simulation do |s|
        s.show(nil, {
          :id => 46,
          :slug => "not_found",
          :church_name => new_tenant_name
        }, :path => "/api/accounts/by_nombre/#{new_tenant_name}.json")

        new_tenant = Tenant.find_by_name(new_tenant_name)
        assert_not_nil new_tenant, "A remote tenant was not found with the name #{new_tenant_name.inspect}"
      end
    end
  end

  test "should not try to create a local record twice when 2 or more threads are fetching a new remote resource concurrently" do
    slug = "unique"

    stub(RemoteWithKey).fetch_by(:slug, slug) do
      sleep 0.01
      RemoteWithKey.nosync { RemoteWithKey.create!(slug: slug) }
    end

    afterwards do
      RemoteWithKey.where(slug: slug).delete_all
    end

    refute_raises ActiveRecord::RecordNotUnique do
      concurrently do
        RemoteWithKey.find_by_slug(slug)
      end
    end
  end

  test "should URI escape remote attributes" do
    bad_uri = "http://() { :; }; ping -c 23 0.0.0.0"
    route = "groups/:group_id/tenants/:slug"
    simple_key_path = Tenant.remote_path_for_simple_key("tenants/:slug", :slug, bad_uri)
    composite_key_path = Tenant.remote_path_for_composite_key(route, [:group_id, :slug], [5, bad_uri])

    assert_equal "tenants/http://()%20%7B%20:;%20%7D;%20ping%20-c%2023%200.0.0.0", simple_key_path
    assert_equal "groups/5/tenants/http://()%20%7B%20:;%20%7D;%20ping%20-c%2023%200.0.0.0", composite_key_path
  end




  # ========================================================================= #
  # Expiration                                                                #
  # ========================================================================= #

  test "should not fetch a remote record when a local record is not expired" do
    tenant = Factory(:tenant, :expires_at => 100.years.from_now)
    unexpected_name = "Totally Wonky"

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => tenant.slug,
        :church_name => unexpected_name
      })

      tenant = Tenant.find_by_remote_id(tenant.remote_id)
      assert_not_equal unexpected_name, tenant.name
    end
  end

  test "should fetch a remote record when a local record is expired" do
    tenant = Factory(:tenant, :expires_at => 1.year.ago)
    unexpected_name = "Totally Wonky"

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => tenant.slug,
        :church_name => unexpected_name
      }, :headers => if_modified_since(tenant))

      tenant = Tenant.find_by_remote_id(tenant.remote_id)
      assert_equal unexpected_name, tenant.name
    end
  end

  test "should treat a 304 response as no changes" do
    tenant = Factory(:tenant, :expires_at => 1.year.ago)

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, nil, :status => 304, :headers => if_modified_since(tenant))

      tenant = Tenant.find_by_remote_id(tenant.remote_id)
      assert tenant.expires_at > Time.now, "Tenant should be considered fresh"
      assert_not_nil tenant.remote_id, "The Remote Tenant's id should not be considered nil just because there was no body in the remote response"
    end
  end

  test "should ignore a 503 response" do
    expired_at = 1.year.ago
    tenant = Factory(:tenant, :expires_at => expired_at)

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, nil, :status => 503, :headers => if_modified_since(tenant))

      assert_nothing_raised do
        tenant = Tenant.find_by_remote_id(tenant.remote_id)
      end
      assert_in_delta expired_at, tenant.expires_at, 0.1, "Tenant's expiration date should not have changed"
    end
  end




  # ========================================================================= #
  # Updating                                                                 #
  # ========================================================================= #

  test "should update a record remotely when updating one locally" do
    tenant = Factory(:tenant)
    new_name = "Totally Wonky"

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => "totally-wonky",
        :church_name => tenant.name
      }, :headers => if_modified_since(tenant))

      tenant.nosync = false
      tenant.name = "Totally Wonky"
      assert_equal true, tenant.any_remote_changes?

      # Throws an error if save is not called on the remote resource
      mock(tenant.remote_resource).save { true }

      tenant.save!
      assert_equal "totally-wonky", tenant.slug, "After updating a record, remote data should be merge"
    end
  end

  test "should be able to update resources by different attributes" do
    tenant = RemoteWithKey.where(id: Factory(:tenant).id).first
    new_name = "Totally Wonky"

    RemoteTenant.run_simulation do |s|
      s.show(nil, {
        :id => tenant.id,
        :slug => tenant.slug,
        :church_name => tenant.name
      }, :path => "/api/accounts/by_slug/#{tenant.slug}.json", :headers => if_modified_since(tenant))

      s.update(nil, :path => "/api/accounts/by_slug/#{tenant.slug}.json")

      tenant.nosync = false
      tenant.name = new_name
      assert_equal true, tenant.any_remote_changes?

      tenant.save!

      # pending "Not sure how to test that an update happened"
    end
  end

  test "should fail to update a record locally when failing to update one remotely" do
    tenant = Factory(:tenant)
    new_name = "Totally Wonky"

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => tenant.slug,
        :church_name => tenant.name
      }, :headers => if_modified_since(tenant))
      s.update(tenant.remote_id, :status => 422, :body => {
        :errors => {:church_name => ["is already taken"]}
      })

      tenant.nosync = false
      tenant.name = new_name
      assert_raises(ActiveRecord::RecordInvalid) do
        tenant.save!
      end
      assert_equal ["is already taken"], tenant.errors[:name]
    end
  end




  # ========================================================================= #
  # Creating                                                                  #
  # ========================================================================= #

  test "should create a record remotely when creating one locally" do
    tenant = Tenant.new({
      :slug => "brand_new",
      :name => "Brand New"
    })

    RemoteTenant.run_simulation do |s|
      s.create({
        :id => 143,
        :slug => tenant.slug,
        :church_name => tenant.name
      })

      tenant.save!

      assert_equal true, tenant.remote_resource.persisted?
      assert_equal 143, tenant.remote_id, "After creating a record, remote data should be merge"
    end
  end

  test "should fail to create a record locally when failing to create one remotely" do
    tenant = Tenant.new({
      :slug => "brand_new",
      :name => "Brand New"
    })

    RemoteTenant.run_simulation do |s|
      s.create({
        :errors => {
          :what => ["ever"],
          :church_name => ["is already taken"]}
      }, :status => 422)

      assert_raises(ActiveRecord::RecordInvalid) do
        tenant.save!
      end

      assert_equal ["is already taken"], tenant.errors[:name]
    end
  end

  test "should create a record locally when fetching a new remote resource" do
    new_tenant_id = 17

    assert_equal 0, Tenant.where(:remote_id => new_tenant_id).count,
      "There's not supposed to be a Tenant with the id #{new_tenant_id}."

    assert_difference "Tenant.count", +1 do
      RemoteTenant.run_simulation do |s|
        s.show(new_tenant_id, {
          :id => new_tenant_id,
          :slug => "not_found",
          :church_name => "Not Found"
        })

        new_tenant = Tenant.find_by_remote_id(new_tenant_id)
        assert_not_nil new_tenant, "A remote tenant was not found with the id #{new_tenant_id.inspect}"
      end
    end
  end




  # ========================================================================= #
  # Destroying                                                                #
  # ========================================================================= #

  test "should destroy a record remotely when destroying one locally" do
    tenant = Factory(:tenant)

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => tenant.slug,
        :church_name => tenant.name
      }, :headers => if_modified_since(tenant))

      # Throws an error if save is not called on the remote resource
      mock(tenant.remote_resource).destroy { true }

      tenant.nosync = false
      tenant.destroy
    end
  end

  test "should destroy resources by different attributes" do
    tenant = RemoteWithKey.where(id: Factory(:tenant).id).first
    new_name = "Totally Wonky"

    RemoteTenant.run_simulation do |s|
      s.show(nil, {
        :id => tenant.id,
        :slug => tenant.slug,
        :church_name => tenant.name
      }, :path => "/api/accounts/by_slug/#{tenant.slug}.json", :headers => if_modified_since(tenant))

      s.destroy(nil, :path => "/api/accounts/by_slug/#{tenant.slug}.json")

      tenant.nosync = false
      tenant.destroy
    end
  end

  test "should fail to destroy a record locally when failing to destroy one remotely" do
    tenant = Factory(:tenant)

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => tenant.slug,
        :church_name => tenant.name
      }, :headers => if_modified_since(tenant))

      s.destroy(tenant.remote_id,
        :body => { :errors => { :base => ["nope"] } },
        :status => 422)

      tenant.nosync = false
      tenant.destroy
      assert_equal false, tenant.destroyed?
      assert_equal ["nope"], tenant.errors[:base]
    end
  end

  test "should succeed in destroying a record locally when the remote source is not found" do
    tenant = Factory(:tenant)

    RemoteTenant.run_simulation do |s|
      s.show(tenant.remote_id, {
        :id => tenant.remote_id,
        :slug => tenant.slug,
        :church_name => tenant.name
      }, :headers => if_modified_since(tenant))

      s.destroy(tenant.remote_id,
        :status => 404)

      tenant.nosync = false
      tenant.destroy
      assert_equal true, tenant.destroyed?
    end
  end

  test "should delete a local record when a remote record has been deleted" do
    tenant = Factory(:tenant, :expires_at => 1.year.ago)

    assert_difference "Tenant.count", -1 do
      RemoteTenant.run_simulation do |s|
        s.show(tenant.remote_id, nil, :status => 404, :headers => if_modified_since(tenant))

        tenant = Tenant.where(:remote_id => tenant.remote_id).first
        assert tenant.destroyed?
      end
    end
  end




  # ========================================================================= #
  #  Listing                                                                  #
  # ========================================================================= #

  test "should be able to find all remote resources and sync them with local resources" do
    tenant = Factory(:tenant, :expires_at => 1.year.ago)

    assert_equal 1, Tenant.count, "There's supposed to be 1 tenant"

    # Creates 1 missing resources, updates 1
    assert_difference "Tenant.count", +1 do
      RemoteTenant.run_simulation do |s|
        s.show(nil, [
          { :id => tenant.id,
            :slug => "a-different-slug",
            :church_name => "A Different Name" },
          { :id => tenant.id + 1,
            :slug => "generic-slug",
            :church_name => "Generic Name" }],
          :path => "/api/accounts.json")

        tenants = Tenant.all_by_remote
        assert_equal 2, tenants.length

        assert_equal "a-different-slug", tenant.reload.slug
      end
    end
  end




  # ========================================================================= #
  #  Timeouts                                                                 #
  # ========================================================================= #

  test "should raise a Remotable::TimeoutError when a timeout occurs" do
    assert_raise Remotable::TimeoutError do
      stub(Tenant.remote_model).find do |*args|
        raise ActiveResource::TimeoutError, "it timed out"
      end

      Tenant.find_by_remote_id(15)
    end
  end

  test "should ignore a Remotable::TimeoutError when instantiating a record" do
    tenant = Factory(:tenant, :expires_at => 1.year.ago)

    assert_nothing_raised do
      stub(Tenant.remote_model).find do |*args|
        raise ActiveResource::TimeoutError, "it timed out"
      end

      tenant = Tenant.find_by_remote_id(tenant.remote_id)
      assert_not_nil tenant
    end
  end




private

  def if_modified_since(record)
    {"If-Modified-Since" => Remotable.http_format_time(record.remote_updated_at)}
  end

  def refute_raises(exception)
    yield
  rescue exception
    flunk "#{$!.class} was raised\n#{$!.message}\n#{$!.backtrace.join("\n")}"
  end

end
