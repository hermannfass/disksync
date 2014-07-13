# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'disksync/version'

Gem::Specification.new do |spec|
  spec.name          = "disksync"
  spec.version       = Disksync::VERSION
  spec.authors       = ["Hermann A. Faß"]
  spec.email         = ["hf@zwergfell.de"]
  spec.summary       = %q{Synchronize data between directories.}
  spec.description   = %q{Wrapper for Rsync dedicated to user data backup.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
end
