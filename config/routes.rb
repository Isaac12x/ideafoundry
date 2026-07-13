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

  namespace :local_agent, path: "local-agent" do
    match "tools", to: "tools#index", via: [:get, :post], as: :tools
    post "tools/:tool_name", to: "tools#create", as: :tool
  end

  # Submission review queue
  get "submissions/import", to: "submission_imports#new", as: :new_submission_import
  post "submissions/import/preview", to: "submission_imports#preview", as: :preview_submission_import
  post "submissions/import", to: "submission_imports#create", as: :submission_import
  get "submissions/import/:source/oauth", to: "submission_imports#oauth", as: :oauth_submission_import
  get "submissions/import/:source/oauth/callback", to: "submission_imports#oauth_callback", as: :oauth_callback_submission_import

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
  mount ActionMailbox::Resend::Engine, at: "/rails/action_mailbox/resend"
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
      post :add_to_list
      post :create_version
      post :make_primary
    end
    collection do
      get :archived
      get :uncompleted
      get :search
    end
    resources :attachments, only: [:create, :destroy, :update], controller: :idea_attachments do
      collection do
        patch :reorder
        get :search
      end
      member do
        post :ocr
        post :extract_knowledge
        get :extraction_status
        patch :update
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
    resources :licensors, only: [:create]
    resources :drawings, only: [:new, :show, :create, :update, :destroy]
    resources :agent_tokens, only: [:create, :destroy], controller: :idea_agent_tokens
  end

  # Licensing CRM
  resources :licensors, only: [:show, :update, :destroy] do
    resources :contacts, only: [:create, :destroy], controller: :licensor_contacts
  end
  namespace :licensing do
    get "crm", to: "crm#index"
  end

  # Lists and drag-and-drop functionality
  resources :kanban_boards, only: [:create]

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

  # Think in Images — visual thinking board (idea-scoped or global/KB board)
  resources :mood_images, only: [:create, :update, :destroy]

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
  get 'settings/display', to: 'settings#display', as: :settings_display
  patch 'settings/display', to: 'settings#update_display'
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
  get 'settings/ai-agents', to: 'settings#local_agent', as: :settings_local_agent
  patch 'settings/ai-agents', to: 'settings#update_local_agent'
  post 'settings/ai-agents/run-now', to: 'settings#run_local_agent_now', as: :settings_local_agent_run_now
  post 'settings/ai-agents/questions', to: 'settings#create_local_agent_question', as: :settings_local_agent_questions
  post 'settings/ai-agents/recommendations/:id/approve',
       to: 'settings#approve_local_agent_recommendation',
       as: :settings_local_agent_recommendation_approve
  post 'settings/ai-agents/recommendations/:id/dismiss',
       to: 'settings#dismiss_local_agent_recommendation',
       as: :settings_local_agent_recommendation_dismiss
  get 'settings/local-agent', to: redirect('/settings/ai-agents')
  get 'settings/github', to: 'settings#github', as: :settings_github
  patch 'settings/github', to: 'settings#update_github'
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
  get 'knowledge-base/raw', to: 'kb#raw', as: :kb_raw
  get 'knowledge-base/serve', to: 'kb#serve', as: :kb_serve
  post 'knowledge-base/extract', to: 'kb#extract', as: :kb_extract
  get 'knowledge-base/edit', to: 'kb#edit', as: :kb_edit
  patch 'knowledge-base/save', to: 'kb#fs_save', as: :kb_fs_save
  post 'knowledge-base/fs/create', to: 'kb#fs_create', as: :kb_fs_create
  patch 'knowledge-base/fs/rename', to: 'kb#fs_rename', as: :kb_fs_rename
  patch 'knowledge-base/fs/move', to: 'kb#fs_move', as: :kb_fs_move
  delete 'knowledge-base/fs', to: 'kb#fs_delete', as: :kb_fs_delete
  resources :facts, only: [:create, :destroy]
  resources :maxims, only: [:create, :destroy]

  # Settings - KB folders
  get  'settings/kb/pick-folder', to: 'settings#pick_folder_dialog', as: :settings_kb_pick_folder
  post 'settings/kb/open-folder', to: 'settings#open_kb_folder',    as: :settings_kb_open_folder
  post 'settings/kb/mount-drive', to: 'settings#mount_kb_drive',    as: :settings_kb_mount_drive
  get 'settings/kb', to: 'settings#kb', as: :settings_kb
  patch 'settings/kb', to: 'settings#update_kb'
  get 'settings/activity', to: 'settings#activity', as: :settings_activity

  # Backlog
  resources :build_items, path: "backlog", except: [:show] do
    member do
      patch :toggle
      patch :toggle_checklist_item
      patch :pin
      get :cancel_edit
    end
    collection do
      patch :reorder
      patch :join
    end
  end

  # App self-upgrade
  post "upgrade", to: "upgrades#create", as: :upgrades
  get  "upgrade/status", to: "upgrades#status", as: :upgrade_status

  # Defines the root path route ("/")
  root "lists#index"

  # Catch-all: redirect unmatched routes to root. Use a TEMPORARY (302) redirect so
  # browsers never cache it — a 301 here makes transiently-unmatched paths resolve to
  # "/" forever. Exclude Rails internals and assets so missing assets/source maps 404
  # cleanly instead of returning the home page's HTML (which breaks dynamic imports).
  get "*path", to: redirect("/", status: 302),
      constraints: ->(req) { !req.path.start_with?("/rails/", "/assets/") }
end
