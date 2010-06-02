require 'jdbc_adapter/tsql_helper'

module ::JdbcSpec

  module ActiveRecordExtensions

    def mssql_connection(config)
      require "active_record/connection_adapters/mssql_adapter"
      config[:host] ||= "localhost"
      config[:port] ||= 1433
      config[:url] ||= "jdbc:jtds:sqlserver://#{config[:host]}:#{config[:port]}/#{config[:database]}"
      config[:driver] ||= "net.sourceforge.jtds.jdbc.Driver"
      embedded_driver(config)
    end

  end

  module MsSQL

    include TSqlMethods

    def self.extended(mod)
      unless @lob_callback_added
        ActiveRecord::Base.class_eval do
          def after_save_with_mssql_lob
            self.class.columns.select { |c| c.sql_type =~ /image/i }.each do |c|
              value = self[c.name]
              value = value.to_yaml if unserializable_attribute?(c.name, c)
              next if value.nil?  || (value == '')

              connection.write_large_object(c.type == :binary, c.name, self.class.table_name, self.class.primary_key, quote_value(id), value)
            end
          end
        end

        ActiveRecord::Base.after_save :after_save_with_mssql_lob
        @lob_callback_added = true
      end
      mod.add_version_specific_add_limit_offset
    end

    def self.adapter_matcher(name, *)
      name =~ /sqlserver|tds/i ? self : false
    end

    def self.column_selector
      [/sqlserver|tds/i, lambda {|cfg,col| col.extend(::JdbcSpec::MsSQL::Column)}]
    end

    def self.jdbc_connection_class
      ::ActiveRecord::ConnectionAdapters::MssqlJdbcConnection
    end

    def sqlserver_version
      @sqlserver_version ||= select_value("select @@version")[/Microsoft SQL Server\s+(\d{4})/, 1]
    end

    def add_version_specific_add_limit_offset
      if sqlserver_version == "2000"
        extend SqlServer2000LimitOffset
      else
        extend SqlServerLimitOffset
      end
    end

    def modify_types(tp) #:nodoc:
      super(tp)
      tp[:string] = {:name => "NVARCHAR", :limit => 255}
      if sqlserver_version == "2000"
        tp[:text] = {:name => "NTEXT"}
      else
        tp[:text] = {:name => "NVARCHAR(MAX)"}
      end
      tp
    end

    module Column
      attr_accessor :identity, :is_special

      def simplified_type(field_type)
        case field_type
        when /int|bigint|smallint|tinyint/i                        then :integer
        when /numeric/i                                            then (@scale.nil? || @scale == 0) ? :integer : :decimal
        when /float|double|decimal|money|real|smallmoney/i         then :decimal
        when /datetime|smalldatetime/i                             then :datetime
        when /timestamp/i                                          then :timestamp
        when /time/i                                               then :time
        when /date/i                                               then :date
        when /text|ntext/i                                         then :text
        when /binary|image|varbinary/i                             then :binary
        when /char|nchar|nvarchar|string|varchar/i                 then :string
        when /bit/i                                                then :boolean
        when /uniqueidentifier/i                                   then :string
        end
      end

      def default_value(value)
        return $1 if value =~ /^\(N?'(.*)'\)$/
        value
      end

      def type_cast(value)
        return nil if value.nil? || value == "(null)" || value == "(NULL)"
        case type
        when :integer then unquote(value).to_i rescue value ? 1 : 0
        when :primary_key then value == true || value == false ? value == true ? 1 : 0 : value.to_i
        when :decimal   then self.class.value_to_decimal(unquote(value))
        when :datetime  then cast_to_datetime(value)
        when :timestamp then cast_to_time(value)
        when :time      then cast_to_time(value)
        when :date      then cast_to_date(value)
        when :boolean   then value == true or (value =~ /^t(rue)?$/i) == 0 or unquote(value)=="1"
        when :binary    then unquote value
        else value
        end

      end

      def is_utf8?
        sql_type =~ /nvarchar|ntext|nchar/i
      end

      def unquote(value)
        value.to_s.sub(/\A\([\(\']?/, "").sub(/[\'\)]?\)\Z/, "")
      end

      def cast_to_time(value)
        return value if value.is_a?(Time)
        time_array = ParseDate.parsedate(value)
        time_array[0] ||= 2000
        time_array[1] ||= 1
        time_array[2] ||= 1
        Time.send(ActiveRecord::Base.default_timezone, *time_array) rescue nil
      end

      def cast_to_date(value)
        return value if value.is_a?(Date)
        return Date.parse(value) rescue nil
      end

      def cast_to_datetime(value)
        if value.is_a?(Time)
          if value.year != 0 and value.month != 0 and value.day != 0
            return value
          else
            return Time.mktime(2000, 1, 1, value.hour, value.min, value.sec) rescue nil
          end
        end
        return cast_to_time(value) if value.is_a?(Date) or value.is_a?(String) rescue nil
        value
      end

      # These methods will only allow the adapter to insert binary data with a length of 7K or less
      # because of a SQL Server statement length policy.
      def self.string_to_binary(value)
        ''
      end

    end

    def quote(value, column = nil)
      return value.quoted_id if value.respond_to?(:quoted_id)

      case value
      when String, ActiveSupport::Multibyte::Chars
        value = value.to_s
        if column && column.type == :binary
          "'#{quote_string(JdbcSpec::MsSQL::Column.string_to_binary(value))}'" # ' (for ruby-mode)
        elsif column && [:integer, :float].include?(column.type)
          value = column.type == :integer ? value.to_i : value.to_f
          value.to_s
        elsif !column.respond_to?(:is_utf8?) || column.is_utf8?
          "N'#{quote_string(value)}'" # ' (for ruby-mode)
        else
          super
        end
      when TrueClass             then '1'
      when FalseClass            then '0'
      else                       super
      end
    end

    def quote_string(string)
      string.gsub(/\'/, "''")
    end

    def quote_table_name(name)
      name
    end

    def quote_column_name(name)
      "[#{name}]"
    end

    def quoted_true
      quote true
    end

    def quoted_false
      quote false
    end

    module SqlServer2000LimitOffset
      def add_limit_offset!(sql, options)
        limit = options[:limit]
        if limit
          offset = (options[:offset] || 0).to_i
          start_row = offset + 1
          end_row = offset + limit.to_i
          order = (options[:order] || determine_order_clause(sql))
          sql.sub!(/ ORDER BY.*$/i, '')
          find_select = /\b(SELECT(?:\s+DISTINCT)?)\b(.*)/i
          whole, select, rest_of_query = find_select.match(sql).to_a
          if (start_row == 1) && (end_row ==1)
            new_sql = "#{select} TOP 1 #{rest_of_query}"
            sql.replace(new_sql)
          else
            #UGLY
            #KLUDGY?
            #removing out stuff before the FROM...
            rest = rest_of_query[/FROM/i=~ rest_of_query.. -1]
            #need the table name for avoiding amiguity
            table_name = get_table_name(sql)
            #I am not sure this will cover all bases.  but all the tests pass
            new_order = "#{order}, #{table_name}.id" if order.index("#{table_name}.id").nil?
            new_order ||= order
            new_sql = "#{select} TOP #{limit} #{rest_of_query} WHERE #{table_name}.id NOT IN (#{select} TOP #{offset} #{table_name}.id #{rest} ORDER BY #{new_order}) ORDER BY #{order} "
            sql.replace(new_sql)
          end
        end
      end
    end

    module SqlServerLimitOffset
      def add_limit_offset!(sql, options)
        limit = options[:limit]
        if limit
          offset = (options[:offset] || 0).to_i
          start_row = offset + 1
          end_row = offset + limit.to_i
          order = (options[:order] || determine_order_clause(sql))
          sql.sub!(/ ORDER BY.*$/i, '')
          find_select = /\b(SELECT(?:\s+DISTINCT)?)\b(.*)/i
          whole, select, rest_of_query = find_select.match(sql).to_a
          new_sql = "#{select} t.* FROM (SELECT ROW_NUMBER() OVER(ORDER BY #{order}) AS row_num, #{rest_of_query}"
          new_sql << ") AS t WHERE t.row_num BETWEEN #{start_row.to_s} AND #{end_row.to_s}"
          sql.replace(new_sql)
        end
      end
    end

    def change_order_direction(order)
      order.split(",").collect do |fragment|
        case fragment
        when  /\bDESC\b/i     then fragment.gsub(/\bDESC\b/i, "ASC")
        when  /\bASC\b/i      then fragment.gsub(/\bASC\b/i, "DESC")
        else                  String.new(fragment).split(',').join(' DESC,') + ' DESC'
        end
      end.join(",")
    end

    def supports_ddl_transactions?
      true
    end

    def recreate_database(name)
      drop_database(name)
      create_database(name)
    end

    def drop_database(name)
      execute "USE master"
      execute "DROP DATABASE #{name}"
    end

    def create_database(name)
      execute "CREATE DATABASE #{name}"
      execute "USE #{name}"
    end

    def rename_table(name, new_name)
      execute "EXEC sp_rename '#{name}', '#{new_name}'"
    end

    # Adds a new column to the named table.
    # See TableDefinition#column for details of the options you can use.
    def add_column(table_name, column_name, type, options = {})
      add_column_sql = "ALTER TABLE #{table_name} ADD #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
      add_column_options!(add_column_sql, options)
      # TODO: Add support to mimic date columns, using constraints to mark them as such in the database
      # add_column_sql << " CONSTRAINT ck__#{table_name}__#{column_name}__date_only CHECK ( CONVERT(CHAR(12), #{quote_column_name(column_name)}, 14)='00:00:00:000' )" if type == :date
      execute(add_column_sql)
    end

    def rename_column(table, column, new_column_name)
      execute "EXEC sp_rename '#{table}.#{column}', '#{new_column_name}'"
    end

    def change_column(table_name, column_name, type, options = {}) #:nodoc:
      change_column_type(table_name, column_name, type, options)
      change_column_default(table_name, column_name, options[:default]) if options_include_default?(options)
    end

    def change_column_type(table_name, column_name, type, options = {}) #:nodoc:
      sql = "ALTER TABLE #{table_name} ALTER COLUMN #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
      if options.has_key?(:null)
        sql += (options[:null] ? " NULL" : " NOT NULL")
      end
      execute(sql)
    end

    def change_column_default(table_name, column_name, default) #:nodoc:
      remove_default_constraint(table_name, column_name)
      unless default.nil?
        execute "ALTER TABLE #{table_name} ADD CONSTRAINT DF_#{table_name}_#{column_name} DEFAULT #{quote(default)} FOR #{quote_column_name(column_name)}"
      end
    end

    def remove_column(table_name, column_name)
      remove_check_constraints(table_name, column_name)
      remove_default_constraint(table_name, column_name)
      execute "ALTER TABLE #{table_name} DROP COLUMN [#{column_name}]"
    end

    def remove_default_constraint(table_name, column_name)
      defaults = select "select def.name from sysobjects def, syscolumns col, sysobjects tab where col.cdefault = def.id and col.name = '#{column_name}' and tab.name = '#{table_name}' and col.id = tab.id"
      defaults.each {|constraint|
        execute "ALTER TABLE #{table_name} DROP CONSTRAINT #{constraint["name"]}"
      }
    end

    def remove_check_constraints(table_name, column_name)
      # TODO remove all constraints in single method
      constraints = select "SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE where TABLE_NAME = '#{table_name}' and COLUMN_NAME = '#{column_name}'"
      constraints.each do |constraint|
        execute "ALTER TABLE #{table_name} DROP CONSTRAINT #{constraint["CONSTRAINT_NAME"]}"
      end
    end

    def remove_index(table_name, options = {})
      execute "DROP INDEX #{table_name}.#{index_name(table_name, options)}"
    end

    def columns(table_name, name = nil)
      return [] if table_name =~ /^information_schema\./i
      cc = super
      cc.each do |col|
        col.identity = true if col.sql_type =~ /identity/i
        col.is_special = true if col.sql_type =~ /text|ntext|image/i
      end
      cc
    end

    def _execute(sql, name = nil)
      if sql.lstrip =~ /^insert/i
        if query_requires_identity_insert?(sql)
          table_name = get_table_name(sql)
          with_identity_insert_enabled(table_name) do
            id = @connection.execute_insert(sql)
          end
        else
          @connection.execute_insert(sql)
        end
      elsif sql.lstrip =~ /^(create|exec)/i
        @connection.execute_update(sql)
      elsif sql.lstrip =~ /^\(?\s*(select|show)/i
        repair_special_columns(sql)
        @connection.execute_query(sql)
      else
        @connection.execute_update(sql)
      end
    end

    #SELECT .. FOR UPDATE is not supported on Microsoft SQL Server
    def add_lock!(sql, options)
      sql
    end

    private

    # Turns IDENTITY_INSERT ON for table during execution of the block
    # N.B. This sets the state of IDENTITY_INSERT to OFF after the
    # block has been executed without regard to its previous state
    def with_identity_insert_enabled(table_name, &block)
      set_identity_insert(table_name, true)
      yield
    ensure
      set_identity_insert(table_name, false)
    end

    def set_identity_insert(table_name, enable = true)
      execute "SET IDENTITY_INSERT #{table_name} #{enable ? 'ON' : 'OFF'}"
    rescue Exception => e
      raise ActiveRecord::ActiveRecordError, "IDENTITY_INSERT could not be turned #{enable ? 'ON' : 'OFF'} for table #{table_name}"
    end

    def get_table_name(sql)
      if sql =~ /^\s*insert\s+into\s+([^\(\s,]+)\s*|^\s*update\s+([^\(\s,]+)\s*/i
        $1
      elsif sql =~ /from\s+([^\(\s,]+)\s*/i
        $1
      else
        nil
      end
    end

    def identity_column(table_name)
      @table_columns = {} unless @table_columns
      @table_columns[table_name] = columns(table_name) if @table_columns[table_name] == nil
      @table_columns[table_name].each do |col|
        return col.name if col.identity
      end

      return nil
    end

    def query_requires_identity_insert?(sql)
      table_name = get_table_name(sql)
      id_column = identity_column(table_name)
      if sql.strip =~ /insert into [^ ]+ ?\((.+?)\)/i
        insert_columns = $1.split(/, */).map(&method(:unquote_column_name))
        return table_name if insert_columns.include?(id_column)
      end
    end

    def unquote_column_name(name)
      if name =~ /^\[.*\]$/
        name[1..-2]
      else
        name
      end
    end

    def get_special_columns(table_name)
      special = []
      @table_columns ||= {}
      @table_columns[table_name] ||= columns(table_name)
      @table_columns[table_name].each do |col|
        special << col.name if col.is_special
      end
      special
    end

    def repair_special_columns(sql)
      special_cols = get_special_columns(get_table_name(sql))
      for col in special_cols.to_a
        sql.gsub!(Regexp.new(" #{col.to_s} = "), " #{col.to_s} LIKE ")
        sql.gsub!(/ORDER BY #{col.to_s}/i, '')
      end
      sql
    end

    def determine_order_clause(sql)
      return $1 if sql =~ /ORDER BY (.*)$/
      sql =~ /FROM +(\w+?)\b/ || raise("can't determine table name")
      table_name = $1
      "#{table_name}.#{determine_primary_key(table_name)}"
    end

    def determine_primary_key(table_name)
      primary_key = columns(table_name).detect { |column| column.primary || column.identity }
      primary_key ? primary_key.name : "id"
    end

  end

end

