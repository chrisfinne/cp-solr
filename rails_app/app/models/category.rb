class Category < ActiveRecord::Base

  class << self
    @@categories = []
    def load_categories
      all.each{|c| @@categories[c.id]=c}
    end


    def find_all_by_id(solr_category_ids)
      load_categories if @@categories.blank?
      solr_category_ids.to_a.collect{|i| @@categories[i.to_i]}.compact
    end

  end

  
end
