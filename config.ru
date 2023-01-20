require './app'

require 'rack/ssl-enforcer'
use Rack::SslEnforcer, :except_environments => 'development'

require 'sass/plugin/rack'
Sass::Plugin.options[:style] = :compressed
use Sass::Plugin::Rack

run Sinatra::Application