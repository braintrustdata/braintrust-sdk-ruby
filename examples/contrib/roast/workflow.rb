# frozen_string_literal: true

config do
  chat(:answer) { no_show_stats! }
end

execute do
  ruby(:question) { "What is the capital of France? Answer in three words or fewer." }
  chat(:answer) { ruby!(:question).value }
end
