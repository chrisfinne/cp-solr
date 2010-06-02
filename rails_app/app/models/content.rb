module Content

  def self.included(base)
    base.class_eval do
      serialize :content if column_names.include?('content')
      serialize :no_search_content if column_names.include?('no_search_content')
      
      def no_search_content_simple_fields
        self.class.const_get('NO_SEARCH_CONTENT_SIMPLE_FIELDS')
      end

      def content_simple_fields
        self.class.const_get('CONTENT_SIMPLE_FIELDS')
      end

      def content_widget_fields
        self.class.const_get('CONTENT_WIDGETS')
      end
      
      simple_content_types = []
      simple_content_types << [:content,base::CONTENT_SIMPLE_FIELDS] if const_defined?('CONTENT_SIMPLE_FIELDS')
      simple_content_types << [:no_search_content,base::NO_SEARCH_CONTENT_SIMPLE_FIELDS] if const_defined?('NO_SEARCH_CONTENT_SIMPLE_FIELDS')
      simple_content_types.each do |arr|
        arr[1].each do |simple|
          if simple.is_a?(Hash) and simple.values.first == :boolean
            simple = simple.keys.first
            define_method(simple.to_s+'=') do |str|
              initialize_content
              self.send(arr[0])[simple.to_sym]= ! (str.nil? or str==false or str=='0' or str==0)
            end
          else
            define_method(simple.to_s+'=') do |str|
              initialize_content
              self.send(arr[0])[simple.to_sym]=str
            end
          end
          define_method(simple) do
            initialize_content
            if ! self.send(arr[0])[simple].nil?
              self.send(arr[0])[simple]
            end
          end
        end
      end
      
      base::CONTENT_WIDGETS.each do |widget|
        define_method(widget) do
          initialize_content
          if content[:widgets][widget] and content[:widgets][widget][:body].present?
            content[:widgets][widget][:body]
          end
        end

        define_method(widget.to_s+'=') do |str|
          initialize_content
          self.content[:widgets][widget] ||= {}
          self.content[:widgets][widget][:body] = str
        end

        widget_title=widget.to_s+'_title'
        define_method(widget_title) do
          initialize_content
          if content[:widgets][widget] and content[:widgets][widget][:title].present?
            content[:widgets][widget][:title]
          end
        end

        define_method(widget_title+'=') do |str|
          initialize_content
          self.content[:widgets][widget] ||= {}
          self.content[:widgets][widget][:title] = str
        end
      end if const_defined?('CONTENT_WIDGETS')

      def initialize_content
        self.content ||= {} if respond_to?(:content)
        self.no_search_content ||= {} if respond_to?(:no_search_content)
        self.content[:widgets] ||= {} if self.class.const_defined?('CONTENT_WIDGETS')
      end

      def to_param
        if respond_to?(:url_keywords)
          clean_url_keywords("#{id} #{url_keywords}")
        else
          id.to_s
        end
      end
      
      # Available extra boxes
      def box_keys
        [:box_1, :box_2, :box_3, :box_4, :box_5]
      end
    end
  end
end