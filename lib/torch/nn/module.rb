module Torch
  module NN
    class Module
      include Utils

      def initialize
        @training = true
        @parameters = {}
        @buffers = {}
        @modules = {}
      end

      def forward
        raise NotImplementedError
      end

      def register_buffer(name, tensor)
        # TODO add checks
        @buffers[name] = tensor
        instance_variable_set("@#{name}", tensor)
      end

      def register_parameter(name, param)
        # TODO add checks
        @parameters[name] = param
      end

      def add_module(name, mod)
        # TODO add checks
        @modules[name] = mod
      end

      def _apply(fn)
        children.each do |mod|
          mod._apply(fn)
        end

        instance_variables.each do |key|
          param = instance_variable_get(key)
          if param.is_a?(Parameter)
            param_applied = nil
            Torch.no_grad do
              param_applied = fn.call(param)
            end
            # TODO should_use_set_data
            instance_variable_set(key, Parameter.new(param_applied, requires_grad: param.requires_grad))

            if param.grad
              grad_applied = nil
              Torch.no_grad do
                grad_applied = fn.call(param.grad)
              end
              # TODO should_use_set_data
              instance_variable_get(key).grad = grad_applied.requires_grad!(param.grad.requires_grad)
            end
          end
        end

        @buffers.each_key do |k|
          buf = @buffers[k]
          unless buf.nil?
            @buffers[k] = fn.call(buf)
            instance_variable_set("@#{k}", @buffers[k])
          end
        end

        self
      end

      def apply(fn)
        children.each do |mod|
          mod.apply(fn)
        end
        fn.call(self)
        self
      end

      # TODO add device
      def cuda
        _apply ->(t) { t.cuda }
      end

      def cpu
        _apply ->(t) { t.cpu }
      end

      def type(dst_type)
        _apply ->(t) { t.type(dst_type) }
      end

      def float
        _apply ->(t) { t.floating_point? ? t.float : t }
      end

      def double
        _apply ->(t) { t.floating_point? ? t.double : t }
      end

      def half
        _apply ->(t) { t.floating_point? ? t.half : t }
      end

      # modifies in-place
      def to(device)
        convert = lambda do |t|
          t.to(device)
        end

        _apply(convert)
      end

      def call(*input, **kwargs)
        forward(*input, **kwargs)
      end

      def state_dict(destination: nil)
        destination ||= {}
        named_parameters.each do |k, v|
          destination[k] = v
        end
        destination
      end

      # TODO add strict option
      # TODO match PyTorch behavior
      def load_state_dict(state_dict)
        state_dict.each do |k, input_param|
          k1, k2 = k.split(".", 2)
          mod = named_modules[k1]
          if mod.is_a?(Module)
            param = mod.named_parameters[k2]
            if param.is_a?(Parameter)
              Torch.no_grad do
                param.copy!(input_param)
              end
            else
              raise Error, "Unknown parameter `#{k2}` in module `#{k1}`"
            end
          else
            raise Error, "Unknown module: #{k1}"
          end
        end

        # TODO return missing keys and unexpected keys
        nil
      end

      def parameters
        named_parameters.values
      end

      def named_parameters(prefix: "", recurse: true)
        params = {}
        if recurse
          named_children.each do |name, mod|
            params.merge!(mod.named_parameters(prefix: "#{prefix}#{name}.", recurse: recurse))
          end
        end
        instance_variables.each do |name|
          param = instance_variable_get(name)
          params[[prefix, name[1..-1]].join] = param if param.is_a?(Parameter)
        end
        @parameters.each do |name, param|
          params[[prefix, name].join] = param if param
        end
        params
      end

      def buffers
        named_buffers.values
      end

      def named_buffers
        @buffers || {}
      end

      def children
        named_children.values
      end

      def named_children
        modules = {}
        instance_variables.each do |name|
          mod = instance_variable_get(name)
          modules[name[1..-1]] = mod if mod.is_a?(Module)
        end
        @modules.each do |name, mod|
          modules[name] = mod
        end
        modules
      end

      def modules
        named_modules.values
      end

      # TODO return enumerator?
      def named_modules(memo: nil, prefix: "")
        ret = {}
        memo ||= Set.new
        unless memo.include?(self)
          memo << self
          ret[prefix] = self
          named_children.each do |name, mod|
            next unless mod.is_a?(Module)
            submodule_prefix = prefix + (!prefix.empty? ? "." : "") + name
            mod.named_modules(memo: memo, prefix: submodule_prefix).each do |m|
              ret[m[0]] = m[1]
            end
          end
        end
        ret
      end

      def train(mode = true)
        @training = mode
        children.each do |mod|
          mod.train(mode)
        end
        self
      end

      def eval
        train(false)
      end

      def requires_grad!(requires_grad: true)
        parameters.each do |p|
          p.requires_grad!(requires_grad)
        end
        self
      end

      def zero_grad
        parameters.each do |param|
          if param.grad
            param.grad.detach!
            param.grad.zero!
          end
        end
      end

      def share_memory
        _apply ->(t) { t.share_memory! }
      end

      def inspect
        name = self.class.name.split("::").last
        if named_children.empty?
          "#{name}(#{extra_inspect})"
        else
          str = String.new
          str << "#{name}(\n"
          named_children.each do |name, mod|
            mod_str = mod.inspect
            mod_str = mod_str.lines.join("  ")
            str << "  (#{name}): #{mod_str}\n"
          end
          str << ")"
        end
      end

      def method_missing(method, *args, &block)
        name = method.to_s
        if named_parameters.key?(name)
          named_parameters[name]
        elsif named_buffers.key?(name)
          named_buffers[name]
        elsif named_modules.key?(name)
          named_modules[name]
        else
          super
        end
      end

      def respond_to?(method, include_private = false)
        name = method.to_s
        named_parameters.key?(name) || named_buffers.key?(name) || named_modules.key?(name) || super
      end

      private

      def extra_inspect
        nil
      end

      def format(str, *vars, **options)
        vars =
          if vars.any?
            vars.map(&:inspect)
          else
            options.map { |k, v| [k, v.inspect] }.to_h
          end
        str % vars
      end

      # used for format
      # remove tensors for performance
      # so we can skip call to inspect
      def dict
        instance_variables.reject { |k| instance_variable_get(k).is_a?(Tensor) }.map { |k| [k[1..-1].to_sym, instance_variable_get(k)] }.to_h
      end
    end
  end
end
