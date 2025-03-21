ENV['RAILS_ENV'] ||= 'test'
ENV['OOD_LOCALES_ROOT'] = Rails.root.join('config/locales').to_s

module Dashboard
  class Application < Rails::Application
    config.paths["app/views"].unshift "test/fixtures/config/views"
  end
end

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'climate_control'
require 'timecop'

class ActiveSupport::TestCase
  # Add more helper methods to be used by all tests here...

  UserDouble = Struct.new(:name, :groups)

  def with_modified_env(options, &block)
    ClimateControl.modify(options, &block)
  end

  def exit_success
    OpenStruct.new(:success? => true, :exitstatus => 0)
  end

  def exit_failure(exit_status=1)
    OpenStruct.new(:success? => false, :exitstatus => exit_status)
  end

  def stub_usr_router
    OodSupport::Process.stubs(:user).returns(UserDouble.new('me', ['me']))
    OodSupport::User.stubs(:new).returns(UserDouble.new('me', ['me']))

    UsrRouter.stubs(:base_path).with(:owner => "me").returns(Pathname.new("test/fixtures/usr/me"))
    UsrRouter.stubs(:base_path).with(:owner => 'shared').returns(Pathname.new("test/fixtures/usr/shared"))
    UsrRouter.stubs(:base_path).with(:owner => 'cant_see').returns(Pathname.new("test/fixtures/usr/cant_see"))
    UsrRouter.stubs(:owners).returns(['me', 'shared', 'cant_see'])
  end

  def stub_sys_apps
    OodAppkit.stubs(:clusters).returns(OodCore::Clusters.load_file('test/fixtures/config/clusters.d'))
    SysRouter.stubs(:base_path).returns(Rails.root.join('test/fixtures/sys_with_gateway_apps'))
  end

  def setup_usr_fixtures
    FileUtils.chmod 0000, 'test/fixtures/usr/cant_see/'
  end

  def teardown_usr_fixtures
    FileUtils.chmod 0755, 'test/fixtures/usr/cant_see/'
  end

  def bc_ele_id(ele)
    "batch_connect_session_context_#{ele}"
  end
end

require 'mocha/minitest'
