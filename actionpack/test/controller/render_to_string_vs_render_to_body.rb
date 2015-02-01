require 'benchmark/ips'
require 'abstract_unit'
require 'stackprof'

Benchmark.ips do |x|
  RENDERER = ApplicationController.renderer.new

  x.report "#slow_render" do
    RENDERER.slow_render template: 'test/hello_world'.freeze
  end

  x.report "#fast_render" do
    RENDERER.render template: 'test/hello_world'.freeze
  end

  x.compare!
end
