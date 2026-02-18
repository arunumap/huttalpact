Rails.application.routes.draw do
  # Auth
  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # App
  resources :contracts do
    resources :documents, only: %i[create destroy], controller: "contract_documents"
    resource :extraction, only: %i[create], controller: "contract_extractions"
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
      get :portal
      get :success
    end
  end
  get "settings", to: redirect("/settings/profile")

  # Billing (legacy redirects)
  get "billing", to: redirect("/settings/billing")

  # Pricing
  resource :pricing, only: %i[show], controller: "pricing"
  mount Pay::Engine, at: "/pay", as: "pay_engine" if defined?(Pay::Engine)

  # Dashboard
  get "dashboard", to: "dashboard#show", as: :dashboard

  # Landing page (context-sensitive root)
  root "pages#home"

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
