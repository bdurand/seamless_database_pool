Gem::Specification.new do |spec|
  spec.name          = "seamless_database_pool"
  spec.version       = File.read(File.expand_path("../VERSION", __FILE__)).chomp
  spec.authors       = ["Brian Durand"]
  spec.email         = ["bbdurand@gmail.com"]
  spec.description   = %q{Add support for master/slave database database clusters in ActiveRecord to improve performance.}
  spec.summary       = %q{Add support for master/slave database clusters in ActiveRecord to improve performance.}
  spec.homepage      = "https://github.com/bdurand/seamless_database_pool"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency(%q<activerecord>, [">= 3.0.20"])
  spec.add_development_dependency(%q<rspec>, [">= 2.0"])
  spec.add_development_dependency(%q<sqlite3>, [">= 0"])
  spec.add_development_dependency(%q<mysql>, [">= 0"])
  spec.add_development_dependency(%q<pg>, [">= 0"])
end
