require 'pathname'
require 'dotenv'

# Dashboard app specific configuration singleton definition
# following the first proposal in:
#
# https://8thlight.com/blog/josh-cheek/2012/10/20/implementing-and-testing-the-singleton-pattern-in-ruby.html
#
# to avoid the traditional singleton approach or using class methods, both of
# which make it difficult to write tests against
#
# instead, ConfigurationSingleton is the definition of the configuration
# then the singleton instance used is a new class called "Configuration" which
# we set in config/boot i.e.
#
# Configuration = ConfigurationSingleton.new
#
# This is functionally equivalent to taking every instance method on
# ConfigurationSingleton and defining it as a class method on Configuration.
#
class ConfigurationSingleton
  attr_writer :app_development_enabled
  attr_writer :app_sharing_enabled

  # FIXME: temporary
  attr_accessor :app_sharing_facls_enabled
  alias_method :app_sharing_facls_enabled?, :app_sharing_facls_enabled

  # @return [String] memoized version string
  def app_version
    @app_version ||= (version_from_file(Rails.root) || version_from_git(Rails.root) || "Unknown").strip
  end

  # @return [String] memoized version string
  def ood_version
    @ood_version ||= (ood_version_from_env || version_from_file('/opt/ood') || version_from_git('/opt/ood') || "Unknown").strip
  end

  def ood_bc_ssh_to_compute_node
    to_bool(ENV['OOD_BC_SSH_TO_COMPUTE_NODE'] || true)
  end

  # @return [String, nil] version string from git describe, or nil if not git repo
  def version_from_git(dir)
    Dir.chdir(Pathname.new(dir)) do
      version = `git describe --always --tags 2>/dev/null`
      version.blank? ? nil : version
    end
  rescue Errno::ENOENT
    nil
  end

  def login_clusters
    OodCore::Clusters.new(
      OodAppkit.clusters
        .select(&:allow?)
        .reject { |c| c.metadata.hidden }
        .select(&:login_allow?)
    )
  end

  # @return [String, nil] version string from VERSION file, or nil if no file avail
  def version_from_file(dir)
    file = Pathname.new(dir).join("VERSION")
    file.read if file.file?
  end

  def ood_version_from_env
    ENV['OOD_VERSION'] || ENV['ONDEMAND_VERSION']
  end

  # The app's configuration root directory
  # @return [Pathname] path to configuration root
  def config_root
    Pathname.new(ENV["OOD_APP_CONFIG_ROOT"] || "/etc/ood/config/apps/dashboard")
  end

  def load_external_config?
    to_bool(ENV['OOD_LOAD_EXTERNAL_CONFIG'] || (rails_env == 'production'))
  end

  # The root directory that holds configuration information for Batch Connect
  # apps (typically each app will have a sub-directory underneath this)
  def bc_config_root
    Pathname.new(ENV["OOD_BC_APP_CONFIG_ROOT"] || "/etc/ood/config/apps")
  end

  def load_external_bc_config?
    to_bool(ENV["OOD_LOAD_EXTERNAL_BC_CONFIG"] || (rails_env == "production"))
  end

  # The file system path to the announcements
  # @return [Pathname, Array<Pathname>] announcement path or paths
  def announcement_path
    if path = ENV["OOD_ANNOUNCEMENT_PATH"]
      Pathname.new(path)
    else
      [
        "/etc/ood/config/announcement.md",
        "/etc/ood/config/announcement.yml",
        "/etc/ood/config/announcements.d"
      ].map {|p| Pathname.new(p)}
    end
  end

  # The paths to the JSON files that store the quota information
  # Can be URL or File path. colon delimited string; though colon in URL is
  # ignored if URL has format: scheme://path (colons preceeding // are ignored)
  #
  # /path/to/quota.json:https://osc.edu/quota.json
  #
  #
  # @return [Array<String>] quota paths
  def quota_paths
    # regex uses negative lookahead to ignore : preceeding //
    ENV.fetch("OOD_QUOTA_PATH", "").strip.split(/:(?!\/\/)/)
  end

  # The threshold for determining if there is sufficient quota remaining
  # @return [Float] threshold factor
  def quota_threshold
    ENV.fetch("OOD_QUOTA_THRESHOLD", 0.95).to_f
  end

  # The paths to the JSON files that store the balance information
  # Can be URL or File path. colon delimited string; though colon in URL is
  # ignored if URL has format: scheme://path (colons preceeding // are ignored)
  #
  # /path/to/balance.json:https://osc.edu/balance.json
  #
  #
  # @return [Array<String>] balance paths
  def balance_paths
    # regex uses negative lookahead to ignore : preceeding //
    ENV.fetch("OOD_BALANCE_PATH", "").strip.split(/:(?!\/\/)/)
  end

  # The threshold for determining if there is sufficient balance remaining
  # @return [Float] threshold factor
  def balance_threshold
    ENV.fetch("OOD_BALANCE_THRESHOLD", 0).to_f
  end

  # The XMoD host
  # @return [String, null] the host, or null if not set
  def xdmod_host
    ENV["OOD_XDMOD_HOST"]
  end

  # Whether or not XDMoD integration is enabled
  # @return [Boolean]
  def xdmod_integration_enabled?
    xdmod_host.present?
  end

  # Load the dotenv local files first, then the /etc dotenv files and
  # the .env and .env.production or .env.development files.
  #
  # Doing this in two separate loads means OOD_APP_CONFIG_ROOT can be specified in
  # the .env.local file, which will specify where to look for the /etc dotenv
  # files. The default for OOD_APP_CONFIG_ROOT is /etc/ood/config/apps/myjobs and
  # both .env and .env.production will be searched for there.
  def load_dotenv_files
    # .env.local first, so it can override OOD_APP_CONFIG_ROOT
    Dotenv.load(*dotenv_local_files)

    # load the rest of the dotenv files
    Dotenv.load(*dotenv_files)

    # load overloads
    Dotenv.overload(*(overload_files(dotenv_files)))
    Dotenv.overload(*(overload_files(dotenv_local_files)))
  end

  def dev_apps_root_path
    Pathname.new(ENV["OOD_DEV_APPS_ROOT"] || "/dev/null")
  end

  def app_development_enabled?
    return @app_development_enabled if defined? @app_development_enabled
    to_bool(ENV['OOD_APP_DEVELOPMENT'] || DevRouter.base_path.directory? || DevRouter.base_path.symlink?)
  end
  alias_method :app_development_enabled, :app_development_enabled?

  def app_sharing_enabled?
    return @app_sharing_enabled if defined? @app_sharing_enabled
    @app_sharing_enabled = to_bool(ENV['OOD_APP_SHARING'])
  end
  alias_method :app_sharing_enabled, :app_sharing_enabled?

  def batch_connect_global_cache_enabled?
    to_bool(ENV["OOD_BATCH_CONNECT_CACHE_ATTR_VALUES"] || true )
  end

  # URL to the Dashboard logo image
  # @return [String, nil] URL of logo image
  def logo_img
    ENV["OOD_DASHBOARD_LOGO"]
  end

  # Whether we display the Dashboard logo image
  # @return [Boolean] whether display logo image
  def logo_img?
    !to_bool(ENV["DISABLE_DASHBOARD_LOGO"])
  end

  # Dashboard logo height used to set the height style attribute
  # @return [String, nil] Logo height
  def logo_height
    ENV["OOD_DASHBOARD_LOGO_HEIGHT"]
  end

  # Sets the Bootstrap 4 navbar type
  # See more about Bootstrap color schemes: https://getbootstrap.com/docs/4.6/components/navbar/#color-schemes
  # @return [String, 'dark'] Default to dark
  def navbar_type
    if ENV['OOD_NAVBAR_TYPE'] == 'inverse' || ENV['OOD_NAVBAR_TYPE'] == 'dark'
      'dark'
    elsif ENV['OOD_NAVBAR_TYPE'] == 'default' || ENV['OOD_NAVBAR_TYPE'] == 'light'
      'light'
    else
      'dark'
    end
  end

  def brand_bg_color
    ENV.values_at('OOD_BRAND_BG_COLOR', 'BOOTSTRAP_NAVBAR_DEFAULT_BG', 'BOOTSTRAP_NAVBAR_INVERSE_BG').compact.first
  end

  def brand_link_active_bg_color
    ENV.values_at('OOD_BRAND_LINK_ACTIVE_BG_COLOR', 'BOOTSTRAP_NAVBAR_DEFAULT_LINK_ACTIVE_BG','BOOTSTRAP_NAVBAR_INVERSE_LINK_ACTIVE_BG' ).compact.first
  end

  def show_all_apps_link?
    to_bool(ENV['SHOW_ALL_APPS_LINK'])
  end

  def developer_docs_url
    ENV['OOD_DASHBOARD_DEV_DOCS_URL'] || "https://go.osu.edu/ood-app-dev"
  end

  # Turbolinks feature flag
  def turbolinks_enabled?
    to_bool(ENV['OOD_TURBOLINKS_ENABLED'])
  end

  def dataroot
    # copied from OodAppkit::AppConfig#set_default_configuration
    # then modified to ensure dataroot is never nil
    #
    # FIXME: note that this would be invalid if the dataroot where
    # overridden in an initializer by modifying OodAppkit.dataroot
    # Solution: in a test, add a custom initializer that changes this, then verify it has
    # no effect or it affects both.
    #
    root = ENV['OOD_DATAROOT'] || ENV['RAILS_DATAROOT']
    if rails_env == "production"
      root ||= "~/#{ENV['OOD_PORTAL'] || 'ondemand'}/data/#{ENV['APP_TOKEN'] || 'sys/dashboard'}"
    else
      root ||= app_root.join("data")
    end

    Pathname.new(root).expand_path
  end

  def locale
    (ENV['OOD_LOCALE'] || 'en').to_sym
  end

  def locales_root
    Pathname.new(ENV['OOD_LOCALES_ROOT'] || "/etc/ood/config/locales")
  end

  # Set the login host in the Native Instructions VNC session partial
  def native_vnc_login_host
    ENV['OOD_NATIVE_VNC_LOGIN_HOST']
  end

  # Set the global configuration directory
  def config_directory
    Pathname.new(ENV['OOD_CONFIG_D_DIRECTORY'] || "/etc/ood/config/ondemand.d")
  end

  # The configured pinned apps
  def pinned_apps
    config.fetch(:pinned_apps, [])
  end

  # The length of the "Pinned Apps" navbar menu
  def pinned_apps_menu_length
    config.fetch(:pinned_apps_menu_length, 6)
  end

  # Setting terminal functionality in files app
  def files_enable_shell_button
    to_bool(config.fetch(:files_enable_shell_button, true))
  end

  # Report performance of activejobs table rendering
  def console_log_performance_report?
    dataroot.join("debug").file? || rails_env != 'production'
  end

  # What to group pinned apps by
  # @return [String, ""] Defaults to ""
  def pinned_apps_group_by
    group_by = config.fetch(:pinned_apps_group_by, "")

    # FIXME: the configuration_singleton shouldn't really know the API of
    # OodApp or subclasses. This is a hack because subclasses of OodApp overload
    # the category and subcategory to something new while saving the original.
    # The fix would be to move this knowledge to somewhere more appropriate than here.
    if group_by == 'category' || group_by == 'subcategory'
      "original_#{group_by}"
    else
      group_by
    end
  end

  # The dashboard's landing page layout. Defaults to nil.
  def dashboard_layout
    config.fetch(:dashboard_layout, nil)
  end

  def can_access_activejobs?
    can_access_core_app? 'activejobs'
  end

  def can_access_files?
    can_access_core_app? 'files'
  end

  def can_access_file_editor?
    can_access_core_app? 'file-editor'
  end

  # Maximum file upload size that nginx will allow from clients in bytes
  #
  # @example No maximum upload size supplied.
  #   file_upload_max #=> "10737420000"
  # @example 20 gigabyte file size upload limit.
  #   file_upload_max #=> "21474840000"
  # @return [String] Maximum upload size for nginx.
  def file_upload_max
    [ENV['FILE_UPLOAD_MAX']&.to_i, ENV['NGINX_FILE_UPLOAD_MAX']&.to_i].compact.min || 10737420000
  end

  # The timeout (seconds) for "generating" a .zip from a directory.
  #
  # Default for OOD_DOWNLOAD_DIR_TIMEOUT_SECONDS is "5" (seconds).
  # @return [Integer]
  def file_download_dir_timeout
    ENV['OOD_DOWNLOAD_DIR_TIMEOUT_SECONDS']&.to_i || 5
  end

  # The maximum size of a .zip file that can be downloaded.
  #
  # Default for OOD_DOWNLOAD_DIR_MAX is 10*1024*1024*1024 bytes.
  # @return [Integer]
  def file_download_dir_max
    ENV['OOD_DOWNLOAD_DIR_MAX']&.to_i || 10737418240
  end

  def allowlist_paths
    (ENV['OOD_ALLOWLIST_PATH'] || ENV['WHITELIST_PATH'] || "").split(':').map{ |s| Pathname.new(s) }
  end

  # default value for opening apps in new window
  # that is used if app's manifest doesn't specify
  # if not set default is true
  #
  # @return [Boolean] true if by default open apps in new window
  def open_apps_in_new_window?
    if ENV['OOD_OPEN_APPS_IN_NEW_WINDOW']
      to_bool(ENV['OOD_OPEN_APPS_IN_NEW_WINDOW'])
    else
      true
    end
  end

  def bc_dynamic_js?
    if ENV['OOD_BC_DYNAMIC_JS']
      to_bool(ENV['OOD_BC_DYNAMIC_JS'])
    else
      to_bool(config.fetch(:bc_dynamic_js, false))
    end
  end

  private

  def can_access_core_app?(name)
    app_dir = Rails.root.realpath.parent.join(name)
    app_dir.directory? && app_dir.join('manifest.yml').readable?
  end

  def config
    @config ||= read_config
  end

  def read_config
    files = Pathname.glob(config_directory.join("*.{yml,yaml,yml.erb,yaml.erb}"))
    files.each_with_object({}) do |f, conf|
      begin
        content = ERB.new(f.read, nil, "-").result(binding)
        yml = YAML.safe_load(content) || {}
        conf.deep_merge!(yml.deep_symbolize_keys)
      rescue => e
        Rails.logger.error("Can't read or parse #{f} because of error #{e}")
      end
    end
  end

  # The environment
  # @return [String] "development", "test", or "production"
  def rails_env
    ENV['RAILS_ENV'] || ENV['RACK_ENV'] || "development"
  end

  # The app's root directory
  # @return [Pathname] path to app root
  def app_root
    Pathname.new(File.expand_path("../../",  __FILE__))
  end

  def dotenv_local_files
    [
      app_root.join(".env.#{rails_env}.local"),
      (app_root.join(".env.local") unless rails_env == "test"),
    ].compact
  end

  def dotenv_files
    [
      (config_root.join("env") if load_external_config?),
      app_root.join(".env.#{rails_env}"),
      app_root.join(".env")
    ].compact
  end

  # reverse list and suffix every path with '.overload'
  def overload_files(files)
    files.reverse.map {|p| p.sub(/$/, '.overload')}
  end

  FALSE_VALUES=[nil, false, '', 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', 'no', 'NO']

  # Bool coersion pulled from ActiveRecord::Type::Boolean#cast_value
  #
  # @return [Boolean] false for falsy value, true for everything else
  def to_bool(value)
    ! FALSE_VALUES.include?(value)
  end
end
