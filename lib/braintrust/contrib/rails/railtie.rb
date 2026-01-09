# frozen_string_literal: true

module Braintrust
  module Contrib
    module Rails
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          Braintrust.auto_instrument!(
            only: Braintrust::Internal::Env.instrument_only,
            except: Braintrust::Internal::Env.instrument_except
          )
        end
      end
    end
  end
end
