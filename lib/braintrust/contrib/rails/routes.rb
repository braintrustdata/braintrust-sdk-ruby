# frozen_string_literal: true

Braintrust::Contrib::Rails::Engine.routes.draw do
  get "/", to: "health#show"
  get "/list", to: "list#show"
  post "/list", to: "list#show"
  post "/eval", to: "eval#create"
end
