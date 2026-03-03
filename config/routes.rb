Rails.application.routes.draw do
  namespace :admin do
    resource :session, only: %i[new create destroy]
    resource :dashboard, only: %i[show], controller: "dashboard"
    root to: "dashboard#show"

    resources :users, only: %i[index show]
    resources :organizations, only: %i[index show]
    resources :ai_usage, only: %i[index], controller: "ai_usage"
    resources :ai_extraction_configs, only: %i[index new create show] do
      member do
        post :activate
      end
    end
    resources :jobs, only: %i[index show] do
      collection do
        get :failed
        get :recurring
      end
    end
    resource :billing, only: %i[show], controller: "billing" do
      post :setup_stripe
      post :configure_portal
      post :sync_all_organizations
      post :sync_organization
    end
    resources :audit_logs, only: %i[index]
    resources :blog_posts do
      member do
        post :publish
        post :unpublish
      end
    end
    resources :blog_categories
    resource :storage, only: %i[show], controller: "storage"
    resource :health, only: %i[show], controller: "health"
  end

  # Auth
  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  get "invitations/:token/accept", to: "invitation_acceptances#show", as: :accept_invitation
  post "switch_organization/:id", to: "organization_switches#create", as: :switch_organization

  # App
  resources :contracts do
    resources :documents, only: %i[create destroy], controller: "contract_documents"
    resource :extraction, only: %i[create], controller: "contract_extractions" do
      post :redetect
    end
    resources :extraction_feedbacks, only: %i[create]
    resource :lease_detail, only: %i[edit update]
    resources :rent_escalations, only: %i[new create edit update destroy]
    resources :lease_options, only: %i[new create edit update destroy]
    resources :lease_milestones, only: %i[new create edit update destroy]
    collection do
      post :create_draft
      post :bulk_archive
      post :bulk_export
    end
  end

  resources :alerts, only: %i[index] do
    member do
      patch :acknowledge
      patch :snooze
    end
  end

  # Redirect old alert_preference path to new settings location
  get "alert_preference", to: redirect("/settings/alerts")

  resources :audit_logs, only: %i[index]

  # Settings
  namespace :settings do
    resource :profile, only: %i[show update], controller: "profile"
    resource :alerts, only: %i[show update], controller: "alerts"
    resource :organization, only: %i[show update], controller: "organization"
    resource :team, only: %i[show], controller: "team"
    resources :members, only: %i[update destroy]
    resources :invitations, only: %i[create destroy] do
      member do
        post :resend
      end
    end
    resource :billing, only: %i[show], controller: "billing" do
      post :checkout
      post :upgrade
      post :downgrade
      post :cancel_downgrade
      post :cancel_subscription
      post :resume_subscription
      get :portal
      get :success
      delete :destroy_account
    end
  end
  get "settings", to: redirect("/settings/profile")

  # Billing (legacy redirects)
  get "billing", to: redirect("/settings/billing")

  # Pricing
  resource :pricing, only: %i[show], controller: "pricing"

  # Blog
  get "blog", to: "blog#index", as: :blog
  get "blog/feed", to: "blog#feed", as: :blog_feed, defaults: { format: :atom }
  get "blog/:slug", to: "blog#show", as: :blog_post

  mount Pay::Engine, at: "/pay", as: "pay_engine" if defined?(Pay::Engine)

  # Dashboard
  get "dashboard", to: "dashboard#show", as: :dashboard

  # Static pages
  get "privacy", to: "pages#privacy", as: :privacy

  # Landing page (context-sensitive root)
  root "pages#home"

  # Legal
  get "terms", to: "pages#terms"

  # Onboarding
  get "onboarding/organization", to: "onboarding#organization"
  patch "onboarding/organization", to: "onboarding#update_organization"
  get "onboarding/contract", to: "onboarding#contract"
  post "onboarding/contract", to: "onboarding#create_contract"
  post "onboarding/contract/skip", to: "onboarding#skip_contract", as: :onboarding_contract_skip
  get "onboarding/invite", to: "onboarding#invite"
  post "onboarding/invite", to: "onboarding#create_invite"
  post "onboarding/complete", to: "onboarding#complete", as: :onboarding_complete

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
