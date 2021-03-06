module Minus5

  module Mssql

    class Adapter

      # params - tiny_tds connection params: https://github.com/rails-sqlserver/tiny_tds
      # with additon of mirror_host
      # Example:
      #    Adapter.new({  :username    => "rails",
      #                   :password    => "",
      #                   :host        => "bedem",
      #                   :mirror_host => "mssql",
      #                   :database    => "activerecord_unittest_mirroring"
      #                })
      def initialize(params)
        load_params params
        @params_cache = {}
        connect
      end
      
      private

      #FIXME stavio samo ovo de na moram load-at active_resource, a i ne znam koji bi 
      #al malo mi je glupasto da uvijek pisam ovu metodu
      def load_params(params)
        params = YAML.load_file(params) if params.kind_of?(String)
        @params = {}
        params.to_hash.each do |key, value|
          @params[key.to_sym] = value
        end
      end

      public

      # Insert row into table_name.
      # Data is hash {column_name => value, ...}
      # Acutal column names will be discovered from database.
      def insert(table_name, data)
        columns = get_params(table_name).reject{|c| c == "id"}
        values = hash_to_values columns, data
        sql = "insert into #{table_name} (#{columns.join(',')}) values (#{values.join(',')})"
        execute(sql).insert
      end

      # Delete rows from table_name.
      # Data is hash with keys eg. {:id => 123}
      def delete(table_name, data)
        columns, values = hash_to_columns_values(data)
        keys = []
        for i in (0..columns.size-1)
          keys << "#{columns[i]} = #{values[i]}"
        end
        sql = "delete from #{table_name} where #{keys.join(' and ')}"
        execute(sql).cancel
      end

      # Send query to the database. With reconnect in case of db mirroring failover.
      def execute(sql)
        @connection.execute(sql)
      rescue TinyTds::Error => e
        connect
        execute(sql)
      end

      # Returns results first column of the first row.
      def select_value(sql)
        rows = execute(sql).each(:as=>:array)
        return if rows.size == 0
        rows[0][0].kind_of?(Array) ? rows[0][0][0] : rows[0][0]
      end
      
      # Returns array of the values from the first column of all returned rows 
      def select_values(sql)
        rows = execute(sql).each(:as=>:array)
        return [] if rows.size == 0
        (rows[0][0].kind_of?(Array) ? rows[0] : rows).map{|row| row[0] }        
      end

      def select(options)
        if options.kind_of?(String)
          execute(options).each(:symbolize_keys=>true)
        else
          results = execute(options[:sql]).each(:symbolize_keys=>true)
          parse_relations(results, options)
        end
      end

      def parse_relations(results, options)
        options = {:primary_key=>:id}.merge(options)
        return [] if results.size == 0
        return results if results[0].kind_of?(Hash)          
        data = {} #parent indexed by primary_key
        results[0].each{ |row| data[row[options[:primary_key]]] = row }
        options[:relations].each_with_index do |relation, index|
          result = results[index+1] #child result
          result.each do |row|
            #find parent row by foreign key and insert child row in collection
            key = row[relation[:foreign_key]]
            raise "key is nil, in #{row.inspect}" if key.nil?
            data_row = data[key]
            raise "parent row not found, for key #{key}" unless data_row
            if relation[:type] == :one_to_many
              data_row[relation[:name]] = [] unless data_row[relation[:name]]
              data_row[relation[:name]] << row
            elsif relation[:type] == :one_to_one
              #merge child row with parent
              if relation[:name]
                data_row[relation[:name]] = row
              else                
                data_row.merge!(row.reject{|key, value| key == relation[:foreign_key]})
              end
            end
          end
        end
        options[:return_hash] ? data : results[0]
      end

      def create_table(schema, table, columns_def)
        execute <<-SQL
          if not exists(select * 
                        from sys.tables 
                        inner join sys.schemas on tables.schema_id = schemas.schema_id 
                        where 
                          tables.name = '#{table}' 
                          and schemas.name = '#{schema}')
            create table #{schema}.#{table} (#{columns_def})
        SQL
      end

      def host
        return @params[:host]
      end
      private
      
      def connect
        if mirror_defined? 
          unless (connect! rescue false)
            to_mirror 
            connect!
          end
        else
          connect!
        end
      end

      #raises error on failed connection
      def connect!
        @connection = TinyTds::Client.new(@params)
        on_connect
        true
      end

      def on_connect
        execute "set ANSI_NULLS on"
        execute "set ANSI_WARNINGS on"
      end

      def mirror_defined?
        !@params[:mirror_host].nil?
      end

      # Switch host and mirror_host in @params
      def to_mirror
        return unless mirror_defined?
        host = @params[:host]
        @params[:host] = @params[:mirror_host]
        @params[:mirror_host] = host
        @params[:dataserver] = "#{@params[:host]}:#{@params[:port] || 1433}"
      end

      # Read table or stored procedure param names from database.
      # Returns array of table column names or stored procedure param
      def get_params(name)
        @params_cache[name] ||=
          begin
            sql = "select name from sys.syscolumns where id = object_id('#{name}')"
            @connection.execute(sql).each.map{|row| row["name"]}
          end
      end

      def hash_to_values(columns, data)
        values = columns.map do |column|
          value = data[column.to_sym]
          value = data[column.to_s]  if value.nil?
          if column == "time" && value.kind_of?(String)
            value = Time.parse(value)
          end
          if value.nil?
            'null'
          elsif value.kind_of?(String)
            #"'#{value.gsub("\'","''")}'"
            "'#{@connection.escape(value)}'"
          elsif value.kind_of?(Date)
            "'#{value.strftime("%Y-%m-%d")}'"
          elsif value.kind_of?(Time) || value.kind_of?(DateTime)
            "'#{value.strftime("%Y-%m-%d %H:%M:%S")}'"
          elsif value.kind_of?(Integer) || value.kind_of?(Fixnum) || value.kind_of?(Bignum) || value.kind_of?(Float) || value.kind_of?(Rational)
            "#{value.to_s}"
          else
            "'#{@connection.escape(value.to_s)}'"
          end
        end
        values
      end

      def hash_to_columns_values(data)
        columns = data.each_key.map{|key| key.to_s}
        [columns, hash_to_values(columns, data)]
      end

    end

  end

end
