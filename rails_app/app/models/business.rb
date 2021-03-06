require 'parse_contact_info'
class Business < ActiveRecord::Base
  NO_SEARCH_CONTENT_SIMPLE_FIELDS=[:crawl_emails, :year_established, :headshot_url, :other_image_url, :other2_image_url, :add_ecosystem_ids, :del_ecosystem_ids, :ecosystem_category_custom_names, :remove_second_degree_ids, :business_radius, :other_emails, :other_phones]
  CONTENT_SIMPLE_FIELDS=[:keywords, :license_number, :page_title, :page_description, :url_keywords, :show_schools_within_miles, :scraped_content, :tag_line, :awards, :business_type, :other_groups]
  CONTENT_WIDGETS = [:areas_served, :services_provided, :box_1, :box_2, :box_3, :box_4, :box_5]

#  include Geocode
#  include FindWithin
  include Content
#  include HasRelationships
  
  
  def self.index_all(index,num_slices)
    logger = ActiveSupport::BufferedLogger.new("#{RAILS_ROOT}/log/solr-index-#{index}.log")

    RSolr.load_java_libs
    if File.exists?("/Users/chrisfinne/code/cp-solr/solr/lib/spatial-solr-1.0-RC5.jar")
      require "/Users/chrisfinne/code/cp-solr/solr/lib/spatial-solr-1.0-RC5.jar"
    else
      require  "/var/www/cp/solr/solr/lib/spatial-solr-1.0-RC5.jar"
    end
    
    base_path = "/Users/chrisfinne/code/cp-solr/solr/"
    base_path = "/var/www/cp/solr/solr/" if File.exists?("/var/www/cp/solr/solr/")
    
    c=RSolr.connect :direct, :solr_home=>"#{base_path}/core#{index}"
    inc=(Business.last.id / num_slices).to_i
    start = index * inc
    the_end = start + inc
    logger.info "Load categories: #{Category.load_categories}"
    logger.info "start biz batches for #{start}:#{the_end}"
    h=nil
    t=Time.now
    commit_index=0
    new_batch_start_id=1
    Business.find_in_batches(:conditions=>"id > #{start} AND id <= #{the_end} AND delta=1", :batch_size=>100) do |group|
      c.add(group.collect(&:to_solr))
      commit_index+=1
      logger.info("== #{index} #{Time.now - t}s ::: #{group.last.id} : #{start}/#{the_end}  #{((group.last.id - start) / (the_end - start)).to_i}%")
      t=Time.now
      if commit_index > 100
        commit_time=Time.now
        c.commit
        Business.connection.update "UPDATE businesses SET delta=0 WHERE id >= #{new_batch_start_id} AND id <= #{group.last.id} AND delta=1"
        logger.info("== #{index} COMMITTED #{Time.now - commit_time}s")
        commit_index=0
        new_batch_start_id=group.last.id
      end
    end
    logger.info "DONE INDEXING - optimizing #{index}"
    c.optimize
    logger.info "DONE OPTIMIZING #{index}"
  end
  
  def solr_id
    id
  end
  
  def to_solr
    @solr_hash ||= {:id=>solr_id, :db_id=>id, :klass=>'Business',
      :name=>name, :contact_last_name_sort=>contact_last_name, :contact_name=>contact_name, :contact_name_blank=>contact_name.blank?,
      :description=>description,
      :category_names=>categories.collect(&:name),
      :high_text=>[tag_line], 
      :text=>[content, 
        categories.collect(&:keywords), categories.collect(&:description), categories.collect(&:govt_description), categories.collect(&:content),
        testimonials_published_text
        ].flatten, 
      :created_at=>created_at.try(:utc).try(:iso8601), :updated_at=>updated_at.try(:utc).try(:iso8601),
      :address=>address, :city=>city, :state=>state, :full_state=>full_state, :zip=>zip, 
      :phones=>[phone,fax].reject(&:blank?).collect{|p| ParseContactInfo.to_phone(p,country)},
      :emails=>[email]+crawl_emails.to_a+other_emails.to_a,
      :lat=>lat, :lng=>lng, 
      :path=>to_param,
      :contactability=>contactability,
      :is_group=>group_id.present?,
#      :lat_rad=>lat_radians, :lng_rad=>lng_radians, 
#      :cp_score=>cp_score,
#      :location_hash=>geohash, 
#      :location=>"#{lat},#{lng}",
      :category_ids=>solr_category_ids
#      , :relationship_ids=>solr_first_degree_ids
    }
  end
  
  def has_testimonial?
    @@business_ids_with_testimonials ||= connection.select_values("SELECT DISTINCT business_id FROM testimonials WHERE published=1").collect(&:to_i)
    @@business_ids_with_testimonials.include?(self.id)
  end
  
  def testimonials_published_text
    return [] unless has_testimonial?
    self.class.connection.select_all("SELECT first_name, last_name, title, company_name, body FROM testimonials WHERE business_id=#{id} AND published=1").
      collect{|t| "#{t['first_name']} #{t['last_name']} #{t['title']} #{t['company_name']} #{t['body']}"}
  end
  
  
  def contactability
    return 50 if user_id
    c=0
    c+=1 if phone
    c+=5 if fax
    c+=4 if url.present?
    c+=4 if crawl_emails.present?
    c+=5 if other_emails.present?
    c+=20 if email.present?
    c+=5 if data_source=='car-scrape' or data_source=="ca-bar"
    c+=4 if data_source=='yl' or data_source=='contact'
    c
  end
  
  def contact_name
    "#{contact_first_name} #{contact_last_name}".strip
  end
  
  def to_param
    clean_url_keywords("#{id} #{name} #{city} #{full_state} #{zip}")
  end
  
  def full_state
    Location.to_state(state)
  end

  def calculate_cp_score
    self.cp_score = contactability
  end


  # From Global
  def clean_url_keywords(str='')
    str.downcase.gsub(' ','-').gsub(/[^a-z0-9\-]/,'').gsub(/-+/,'-').gsub(/\A-+/,'').gsub(/-+\Z/,'').strip.chomp('-') unless str.blank?
  end
  
  # Relationship performance Hacks
  def solr_category_ids
    @solr_category_ids ||= self.class.connection.select_values("SELECT DISTINCT category_id FROM categories_listings WHERE business_id=#{self.id}")
  end
  
  def categories
    @categories ||= Category.find_all_by_id(solr_category_ids)
  end
  
  def solr_first_degree_ids
    @solr_first_degree_ids ||= self.class.connection.select_values("SELECT DISTINCT target_id FROM relationships WHERE source_id=#{self.id}")
  end
  

end
