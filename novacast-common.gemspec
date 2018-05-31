# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'novacast-common/version'

Gem::Specification.new do |spec|
  spec.name          = "novacast-common"
  spec.version       = Novacast::Common::VERSION
  spec.authors       = ['lscspirit']
  spec.email         = ['lscspirit@hotmail.com']

  spec.summary       = 'Common logic for Novacast services'
  spec.description   = 'Common logic for Novacast services'
  spec.homepage      = ''
  spec.license       = 'None'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = ''
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ['lib']

  spec.add_dependency 'connection_pool', '~> 2.2', '>= 2.2.0'
  spec.add_dependency 'jwt', '~> 2.0'

  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.7.0'
  spec.add_development_dependency 'faker', '~> 1.8.7'
  spec.add_development_dependency 'fakeredis', '~> 0.7.0'
end
