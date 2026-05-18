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
      resources :ideas, only: [] do
        resource :document, only: [:show, :update], controller: :idea_documents
      end
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

  get "recovery-secret", to: "recovery_secrets#new", as: :recovery_secret
  post "recovery-secret", to: "recovery_secrets#create"
  delete "recovery-secret", to: "recovery_secrets#destroy"

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
      get :uncompleted
      get :search
    end
    resources :attachments, only: [], controller: :idea_attachments do
      collection do
        patch :reorder
      end
      member do
        post :ocr
      end
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
    resources :agent_tokens, only: [:create, :destroy], controller: :idea_agent_tokens
  end

  # Lists and drag-and-drop functionality
  resources :lists do
    member do
      post :send_email
      post :add_idea
      delete :remove_idea
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
  patch 'settings', to: 'settings#update_display'
  get 'settings/scoring', to: 'settings#scoring'
  patch 'settings/scoring', to: 'settings#update_scoring'
  get 'settings/scoring/weights', to: 'settings#get_scoring_weights'
  get 'settings/email', to: 'settings#email'
  patch 'settings/notifications', to: 'settings#update_notifications'
  get 'settings/security', to: 'settings#security'
  patch 'settings/security', to: 'settings#update_security'
  post 'settings/security/encrypt-database', to: 'settings#encrypt_database', as: :settings_security_encrypt_database
  get 'settings/idea-work-tokens', to: 'settings#idea_work_tokens', as: :settings_idea_work_tokens
  patch 'settings/idea-work-tokens', to: 'settings#update_idea_work_tokens'
  get 'settings/topologies', to: 'settings#topologies'
  patch 'settings/topologies', to: 'settings#update_topologies'
  get 'settings/lists', to: 'settings#lists'
  patch 'settings/lists', to: 'settings#update_lists'
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

  get 'ideas/:idea_id/agent-skill.md', to: 'idea_agent_tokens#skill', as: :idea_agent_skill

  # Typing fingerprint lock
  get 'typing-lock', to: 'typing_locks#new', as: :typing_lock
  post 'typing-lock/lock', to: 'typing_locks#lock', as: :lock_typing_lock
  post 'typing-lock/verify', to: 'typing_locks#verify', as: :verify_typing_lock
  post 'typing-lock/authenticator', to: 'typing_locks#verify_authenticator', as: :verify_authenticator_typing_lock
  post 'typing-lock/voice-id', to: 'typing_locks#verify_voice', as: :verify_voice_id_typing_lock
  post 'typing-lock/voice-id/transcribe', to: 'typing_locks#transcribe_voice', as: :transcribe_voice_id_typing_lock
  patch 'typing-lock/activity', to: 'typing_locks#activity', as: :typing_lock_activity
  get 'typing-lock/enroll', to: 'typing_locks#enroll', as: :enroll_typing_lock
  post 'typing-lock/enroll', to: 'typing_locks#create', as: :typing_lock_enrollment
  get 'typing-lock/voice-id/enroll', to: 'typing_locks#enroll_voice', as: :enroll_voice_id
  post 'typing-lock/voice-id/enroll', to: 'typing_locks#create_voice', as: :voice_id_enrollment

  # KB section
  get 'knowledge-base', to: 'kb#index', as: :kb
  get 'kb', to: redirect('/knowledge-base')
  get 'knowledge-base/file', to: 'kb#file', as: :kb_file
  get 'kb/file', to: redirect('/knowledge-base/file')
  resources :facts, only: [:create, :destroy]

  # Settings - KB folders
  get 'settings/kb', to: 'settings#kb', as: :settings_kb
  patch 'settings/kb', to: 'settings#update_kb'

  # Backlog
  resources :build_items, path: "backlog", except: [:show] do
    member do
      patch :toggle
      patch :toggle_checklist_item
      get :cancel_edit
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
