require 'active_support/core_ext/hash/keys'

module ActionController
  # ActionController::Renderer allows to render arbitrary templates
  # without requirement of being in controller actions.
  #
  # You get a concrete renderer class by invoking ActionController::Base#renderer.
  # For example,
  #
  #   ApplicationController.renderer
  #
  # It allows you to call method #render directly.
  #
  #   ApplicationController.renderer.render template: '...'
  #
  # You can use a shortcut on controller to replace previous example with:
  #
  #   ApplicationController.render template: '...'
  #
  # #render method allows you to use any options as when rendering in controller.
  # For example,
  #
  #   FooController.render :action, locals: { ... }, assigns: { ... }
  #
  # The template will be rendered in a Rack environment which is accessible through
  # ActionController::Renderer#env. You can set it up in two ways:
  #
  # *  by changing renderer defaults, like
  #
  #       ApplicationController.renderer.defaults # => hash with default Rack environment
  #
  # *  by initializing an instance of renderer by passing it a custom environment.
  #
  #       ApplicationController.renderer.new(method: 'post', https: true)
  #
  class Renderer
    class_attribute :controller, :defaults
    # Rack environment to render templates in.
    attr_reader :env

    class << self
      delegate :render, to: :new

      # Create a new renderer class for a specific controller class.
      def for(controller)
        Class.new self do
          self.controller = controller
          self.defaults = {
            http_host: 'example.org',
            https: false,
            method: 'get',
            script_name: '',
            'rack.input' => ''
          }
        end
      end
    end

    # Accepts a custom Rack environment to render templates in.
    # It will be merged with ActionController::Renderer.defaults
    def initialize(env = {})
      @env = normalize_keys(defaults).merge normalize_keys(env)
      @env['action_dispatch.routes'] = controller._routes
    end

    # Render templates with any options from ActionController::Base#render_to_string.
    def slow_render(*args)
      raise 'missing controller' unless controller?

      instance = controller.build_with_env(env)
      instance.render_to_string(*args)
    end

    RENDER_FORMATS_IN_PRIORITY = [:body, :text, :plain, :html]

    def render(*args)
      raise 'missing controller' unless controller?

      instance = controller.build_with_env(env)
      action   = args.first
      options  = args.extract_options!

      # AcstractController::Rendering#_normalize_args
      #   rails/actionpack/lib/abstract_controller/rendering.rb:80

      # ActionView::Rendering#_normalize_args does the same already.
      #options = if action.is_a? Hash
      #  action
      #else
      #  options
      #end

      # ActionView::Rendering#_normalize_args
      #   rails/actionview/lib/action_view/rendering.rb:116
      case action
      when NilClass
      when Hash
        options = action
      when String, Symbol
        action = action.to_s
        key = action.include?(?/) ? :template : :action
        options[key] = action
      else
        options[:partial] = action
      end

      # ActionController::Rendering#_normalize_args
      #   rails/actionpack/lib/action_controller/metal/rendering.rb:67
      # invalid as #render doesn't take blocks.
      # options[:update] = blk if block_given?

      # AbstractController::Rendering#_normalize_render
      #   rails/actionpack/lib/abstract_controller/rendering.rb:107
      if defined?(request) && request && request.variant.present?
        options[:variant] = request.variant
      end

      # ActionController::Rendering#_normalize_text
      #   rails/actionpack/lib/action_controller/metal/rendering.rb:92
      #RENDER_FORMATS_IN_PRIORITY.each do |format|
      #  if options.key?(format) && options[format].respond_to?(:to_text)
      #    options[format] = options[format].to_text
      #  end
      #end

      # ActionController::Rendering#_normalize_options
      #   rails/actionpack/lib/action_controller/metal/rendering.rb:74
      #if options[:html]
      #  options[:html] = ERB::Util.html_escape(options[:html])
      #end

      # `render nothing: true` doesn't make sense.
      #if options.delete(:nothing)
      #  options[:body] = nil
      #end

      # no need to set status.
      #if options[:status]
      #  options[:status] = Rack::Utils.status_code(options[:status])
      #end

      # AcstractController::Rendering#_normalize_options
      #   rails/actionpack/lib/abstract_controller/rendering.rb:90
      #options = options

      # ActionView::Rendering#_normalize_options
      #   rails/actionview/lib/action_view/rendering.rb:136
      # :partial option won't work as #action_name always returns nil.
      #if options[:partial] == true
      #  options[:partial] = instance.action_name
      #end

      if (options.keys & [:partial, :file, :template]).empty?
        options[:prefixes] ||= instance._prefixes
      end

      options[:template] ||= options[:action].to_s

      # ActionView::Layouts#_normalize_options
      #   rails/actionview/lib/action_view/layouts.rb:342
      if (options.keys & [:inline, :partial]).empty? || options.key?(:layout)
        layout = options.delete(:layout) { :default }

        # ActionView::Layouts#_layout_for_option
        #   rails/actionview/lib/action_view/layouts.rb:381
        name = case layout
               when String     then (layout.is_a?(String) && layout !~ /\blayouts/ ? "layouts/#{layout}" : layout)
               when Proc       then layout
               when true       then Proc.new { instance.send(:_default_layout, true)  }
               when :default   then Proc.new { instance.send(:_default_layout, false) }
               when false, nil then nil
               else
                 raise ArgumentError,
                 "String, Proc, :default, true, or false, expected for `layout'; you passed #{layout.inspect}"
               end

        options[:layout] = name
      end

      instance.render_to_body(options)
    end

    private
      def normalize_keys(env)
        http_header_format(env).tap do |new_env|
          handle_method_key! new_env
          handle_https_key!  new_env
        end
      end

      def http_header_format(env)
        env.transform_keys do |key|
          key.is_a?(Symbol) ? key.to_s.upcase : key
        end
      end

      def handle_method_key!(env)
        if method = env.delete('METHOD')
          env['REQUEST_METHOD'] = method.upcase
        end
      end

      def handle_https_key!(env)
        if env.has_key? 'HTTPS'
          env['HTTPS'] = env['HTTPS'] ? 'on' : 'off'
        end
      end
  end
end
