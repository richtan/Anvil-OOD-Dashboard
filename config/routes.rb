require "authz/app_developer_constraint"

Rails.application.routes.draw do

  # in production, if the user doesn't have access to the files app directory, we hide the routes
  if Configuration.can_access_files?
    constraints filepath: /.+/ do
      get "files/fs(/*filepath)" => "files#fs", :defaults => { :format => "html", :filepath => "/" }, :format => false, as: :files
      put "files/fs/*filepath" => "files#update", :format => false, :defaults => { :format => "json" }

      # TODO: deprecate these routes after updating OodAppkit to use the new routes above
      # backwards compatibility with the "api" routes that OodAppkit provides
      # and are used by File Editor and Job Composer
      get "files/api/v1/fs(/*filepath)" => "files#fs", :defaults => { :format => "html", :filepath => "/" }, :format => false
      put "files/api/v1/fs/*filepath" => "files#update", :format => false, :defaults => { :format => "json" }
    end
    post "files/upload"

    get "files", to: redirect("files/fs#{Dir.home}")

    resources :transfers, only: [:show, :create, :destroy]
  end

  if Configuration.can_access_file_editor?
    # App file editor
    get "files/edit/*filepath" => "files#edit", defaults: { :path => "/", :format => "html" }, format: false
    get "files/edit" => "files#edit", :defaults => { :path => "/", :format => "html" }, format: false
  end

  namespace :batch_connect do
    resources :sessions, only: [:index, :destroy]
    scope "*token", constraints: { token: /((usr\/[^\/]+)|dev|sys)\/[^\/]+(\/[^\/]+)?/ } do
      resources :session_contexts, only: [:new, :create]
      root "session_contexts#new"
    end
  end
  get "errors/not_found"
  get "errors/internal_server_error"
  get "dashboard/index"
  get "logout" => "dashboard#logout"

  # analytics request appears in the access logs and google analytics
  get "analytics/:type" => proc { [204, {}, [""]] }, as: "analytics"

  get "apps/show/:name(/:type(/:owner))" => "apps#show", as: "app", defaults: { type: "sys" }
  get "apps/icon/:name(/:type(/:owner))" => "apps#icon", as: "app_icon", defaults: { type: "sys" }
  get "apps/index" => "apps#index"

  if Configuration.app_sharing_enabled?
    get "apps/restart" => "apps#restart"
    get "apps/featured" => "apps#featured"
  end

  # API endpoints
  get "api/balance_usage", action: :get, controller: "api/balance_usage", as: "balance_usage"
  get "api/disk_usage", action: :get, controller: "api/disk_usage", as: "disk_usage"
  get "api/partition_status", action: :get, controller: "api/partition_status", as: "partition_status"
  get "api/news_feed", action: :get, controller: "api/news_feed", as: "news_feed"
  get "api/job_queue", action: :get, controller: "api/job_queue", as: "job_queue"
  get "api/balance_summary", action: :get, controller: "api/balance_summary", as: "balance_summary"

  get "api/userdata", action: :getuserdata, controller: "api/jobs_data"
  get "api/sacctuser", action: :getsacctuser, controller: "api/jobs_data"

  root "dashboard#index"

  # App administration
  scope "admin/:type", constraints: Authz::AppDeveloperConstraint do
    resources :products, except: :destroy, param: :name, constraints: { type: /dev|usr/ } do
      nested do
        scope ":context" do
          resources :permissions, only: [:index, :new, :create, :destroy], param: :name
        end
      end
      member do
        patch "cli/:cmd", to: "products#cli", as: "cli"
      end
      collection do
        get "create_key"
        get "new_from_git_remote"
        post "create_from_git_remote"
      end
    end
  end

  # ActiveJobs which can be disabled in production
  if Configuration.can_access_activejobs?
    get "/activejobs" => "active_jobs#index"
    get "/activejobs/json" => "active_jobs#json", :defaults => { :format => "json" }
    delete "/activejobs" => "active_jobs#delete_job", as: "delete_job"
  end

  get "/jobs_page" => "jobs_page#index", as: "jobs_page"

  get "/myjobs" => "my_jobs#index", as: "my_jobs"
  get "/myjobs/json" => "my_jobs#json"
  delete "/myjobs" => "my_jobs#cancel_jobs", as: "cancel_jobs"

  get "/job/:jobid/json" => "job_info#json"

  match "/404", :to => "errors#not_found", :via => :all
  match "/500", :to => "errors#internal_server_error", :via => :all

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end