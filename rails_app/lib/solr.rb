class Solr
  class << self
    def connection
      @connection ? @connection : set_connection
    end
    
    def set_connection(core=SOLR_CORE)
      if RUBY_PLATFORM =~ /java/
        @connection = RSolr.connect :direct, :solr_home=>"/Users/chrisfinne/code/cp-solr"
      else
        @connection = RSolr.connect :url=>SOLR_URL+core
      end
    end
    
    def search(opts, http_method = :post)
      opts = opts.reverse_merge(:rows=>20)
      opts[:rows] = opts.delete(:per_page).to_i if opts[:per_page]
      if opts[:page]
        opts[:start] = (opts.delete(:page).to_i - 1) * opts[:rows].to_i
      end
      response = connection.request('/select', opts, :method=>http_method)
      # Doing the POST RSolr returns a string rather than the parsed hash
      # http://github.com/mwmitchell/rsolr/issues/issue/7
      (http_method == :post ? Kernel.eval(response) : response)['response']
    end
    
    def add_to_index(obj, commit=true, wait=false)
      obj = [obj] unless obj.is_a?(Array)
      connection.add obj.collect{|o| o.kind_of?(Hash) ? o : o.to_solr}
      commit_wait(commit,wait)
    end
    
    def remove_from_index(obj, commit=true, wait=false)
      obj = [obj] unless obj.is_a?(Array)
      connection.delete_by_id obj.collect{|o| (o.kind_of?(String) or o.kind_of?(Fixnum)) ? o : o.solr_id}
      commit_wait(commit,wait,true)
    end
    
    def commit_wait(commit,wait,deletes=false)
      connection.update %Q!<commit waitFlush="#{wait}" waitSearcher="#{wait}" expungeDeletes="#{deletes}" />! if commit
    end
    
    def optimize(wait=false)
      connection.update %Q!<optimize waitFlush="#{wait}" waitSearcher="#{wait}" expungeDeletes="true" />!
    end

  end
end

=begin
        # code that queries solr
        tries = 0
        begin
         puts "attempting solr request: #{tries}"
         query_solr
        rescue TimeoutError
         puts "FAILED"
         tries += 1
         retry if tries < 5
         raise "come back later."
        end
=end
