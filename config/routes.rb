Rails.application.routes.draw do
  # Template management
  resources :templates do
    member do
      post :apply
    end
  end

  # Export management
  resources :exports do
    member do
      get :download
    end
    collection do
      post :cleanup_old
    end
  end

  # Programmatic intake API
  namespace :api do
    namespace :v1 do
      resources :submissions, only: [:create, :show]
    end
  end

  # Submission review queue
  resources :submissions, only: [:index, :show, :destroy] do
    member do
      post :approve
      post :reject
      post :reopen
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Action Mailbox ingress routes
  mount ActionMailbox::Engine => "/rails/action_mailbox"

  # Ideas management
  resources :ideas do
    member do
      post :send_email
      post :approve_pending_email
      delete :discard_pending_email
      post :enrich
      get :enrichment_status
      post :archive
      post :restore
    end
    collection do
      get :archived
      get :search
    end
    resources :versions, only: [:index, :show] do
      member do
        post :restore
      end
      collection do
        get :compare
      end
    end
    resources :todo_items, only: [:create, :destroy] do
      member do
        patch :toggle
      end
      collection do
        patch :reorder
      end
    end
    resources :notes, only: [:create, :destroy]
    resources :idea_entries, only: [:create, :update, :destroy]
    resources :drawings, only: [:new, :show, :create, :update, :destroy]
  end

  # Lists and drag-and-drop functionality
  resources :lists do
    member do
      post :send_email
    end
    collection do
      patch :update_idea_position
    end
  end

  # Uploads for TipTap editor images
  resources :uploads, only: [:create]

  # Topology management
  resources :topologies do
    collection do
      patch :reorder
      get :graph_data
    end
    member do
      get :neighborhood
    end
  end

  # Webhook endpoint (API-only, token auth)
  post 'webhooks/external', to: 'webhooks#external'

  # Settings management
  get 'settings', to: 'settings#index'
  get 'settings/scoring', to: 'settings#scoring'
  patch 'settings/scoring', to: 'settings#update_scoring'
  get 'settings/scoring/weights', to: 'settings#get_scoring_weights'
  get 'settings/email', to: 'settings#email'
  patch 'settings/notifications', to: 'settings#update_notifications'
  get 'settings/topologies', to: 'settings#topologies'
  patch 'settings/topologies', to: 'settings#update_topologies'
  get 'settings/idea-tabs', to: 'settings#idea_tabs'
  patch 'settings/idea-tabs', to: 'settings#update_idea_tabs'
  get 'settings/idea_tabs', to: redirect('/settings/idea-tabs')
  get 'settings/templates', to: 'settings#templates'
  get 'settings/templates/new', to: 'templates#new', as: :new_settings_template
  get 'settings/exports', to: 'settings#exports'
  post 'settings/exports', to: 'settings#create_export'
  get 'settings/exports/:id/download', to: 'settings#download_export', as: :settings_export_download
  delete 'settings/exports/:id', to: 'settings#destroy_export', as: :settings_export_destroy
  post 'settings/exports/cleanup', to: 'settings#cleanup_exports'
  patch 'settings/backup', to: 'settings#update_backup'
  post 'settings/backup/now', to: 'settings#create_backup', as: :settings_backup_now
  get 'settings/api_keys', to: 'settings#api_keys'
  post 'settings/api_keys', to: 'settings#create_api_key'
  delete 'settings/api_keys/:id', to: 'settings#destroy_api_key', as: :settings_api_key_destroy

  # Backlog
  resources :build_items, path: "backlog", except: [:show] do
    member do
      patch :toggle
    end
    collection do
      patch :reorder
    end
  end

  # Defines the root path route ("/")
  root "lists#index"

  # Catch-all: redirect unmatched routes to root (exclude Rails internal paths like ActiveStorage)
  get "*path", to: redirect("/"), constraints: ->(req) { !req.path.start_with?("/rails/") }
end
