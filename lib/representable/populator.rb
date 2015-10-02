module Representable
  # we don't use keyword args, because i didn't want to discriminate 1.9 users, yet.
  # this will soon get introduces and remove constructs like options[:binding][:default].

  StopOnNotFound = -> (options) do
    return Pipeline::Stop if options[:fragment] == Binding::FragmentNotFound
    options[:fragment]
  end

  StopOnNil = -> (options) do # DISCUSS: Not tested/used, yet.
    return Pipeline::Stop if options[:fragment].nil?
    options[:fragment]
  end

  OverwriteOnNil = -> (options) do
    if options[:fragment].nil?
      Setter.(options.merge(result: nil))
      return Pipeline::Stop
    end
    options[:fragment] # becomes :result
  end


  # FIXME: how to combine those two guys?
  Default = ->(options) do
    if options[:fragment] == Binding::FragmentNotFound
      return options[:binding].has_default? ? options[:binding][:default] : Pipeline::Stop
    end
    options[:fragment]
  end

  ReturnFragment = ->(options) { options[:fragment] }

  SkipParse = ->(options) do
    # puts "#{options[:binding].name} ret: #{options[:result]}"
    return Pipeline::Stop if options[:binding].evaluate_option(:skip_parse, options)
    options[:fragment]
  end


  Instance = ->(options) do
    options[:binding].evaluate_option(:instance, options)
  end

  Deserialize = ->(options) do
    options[:binding].send(:deserializer).call(options[:fragment], options[:result]) # object.from_hash
  end

  module Function
    class CreateObject
      def call(options)
        object = instance_for(options) || class_for(options)
        # [fragment, object]
      end

    private
      def class_for(options)
        item_class = class_from(options) or raise DeserializeError.new(":class did not return class constant for `#{options[:binding].name}`.")
        item_class.new
      end

      def class_from(options)
        options[:binding].evaluate_option(:class, options) # FIXME: no additional args passed here, yet.
      end

      def instance_for(options)
        Instance.(options)
      end
    end
  end

  CreateObject = Function::CreateObject.new

  Prepare = ->(result:, binding:, **bla) do
    representer = binding.send(:deserializer).send(:prepare, result)
    # raise args.inspect
    representer
  end

  # FIXME: only add when :parse_filter!
  ParseFilter = ->(options) do
    options[:binding].parse_filter(options) # FIXME: nested pipeline!
    options[:result]
  end

  # Setter = ->(value, doc, binding,*) do
  Setter = ->(binding:, result:, **o) do
    binding.set(result)
  end


  class Collect
    def self.[](*functions)
      new(functions)
    end

    def initialize(functions)
      @item_pipeline = Pipeline[*functions].extend(Pipeline::Debug)
    end

    # when stop, the element is skipped. (should that be Skip then?)
    def call(options)
      arr = [] # FIXME : THIS happens in collection deserializer.
      options[:fragment].each_with_index do |item_fragment, i|
        # DISCUSS: we should replace fragment into the existing hash
        result = @item_pipeline.(options.merge(fragment: item_fragment, index: i))

        next if result == Pipeline::Stop
        arr << result
      end

      arr
    end


    class Hash < self
      def call(fragment:, **o)
        {}.tap do |hsh|
          fragment.each { |key, item_fragment| hsh[key] = @item_pipeline.(fragment: item_fragment, **o) }
        end
      end
    end
  end
end