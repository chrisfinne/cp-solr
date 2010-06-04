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
    RSolr.load_java_libs
    if File.exists?("/Users/chrisfinne/code/cp-solr/solr/lib/spatial-solr-1.0-RC4.jar")
      require "/Users/chrisfinne/code/cp-solr/solr/lib/spatial-solr-1.0-RC4.jar"
    else
      require  "/var/www/cp/solr/solr/lib/spatial-solr-1.0-RC4.jar"
    end
    
    base_path = "/Users/chrisfinne/code/cp-solr/solr/"
    base_path = "/var/www/cp/solr/solr/" if File.exists?("/var/www/cp/solr/solr/")
    
    c=RSolr.connect :direct, :solr_home=>"#{base_path}/core#{index}"
    inc=(Business.count / num_slices).to_i
    start = index * inc
    the_end = start + inc
    puts "Load categories: #{Category.load_categories}"
    puts "start biz batches for #{start}:#{the_end}"
    h=nil
    t=Time.now
    Business.find_in_batches(:conditions=>"id > #{start} AND id <= #{the_end}", :batch_size=>100) do |group|
#      puts "loaded #{group.size}"
#      puts "generate hash #{Benchmark.realtime{h=group.collect(&:to_solr)}}s"
#      c.add(h)
      c.add(group.collect(&:to_solr))
      puts("== #{index} #{Time.now - t}s ::: #{group.last.id} : #{start}/#{the_end}")
      t=Time.now
    end
    puts "commiting #{index}"
    c.commit
    puts "optimizing #{index}"
    c.optimize
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
      :text=>[content, categories.collect(&:keywords), categories.collect(&:description), categories.collect(&:govt_description), categories.collect(&:content)].flatten, 
      :created_at=>created_at.try(:utc).try(:iso8601), :updated_at=>updated_at.try(:utc).try(:iso8601),
      :address=>address, :city=>city, :state=>state, :full_state=>full_state, :zip=>zip, 
      :phones=>[phone,fax].reject(&:blank?).collect{|p| ParseContactInfo.to_phone(p,country)},
      :emails=>[email]+crawl_emails.to_a+other_emails.to_a,
      :lat=>lat, :lng=>lng, 
      :path=>to_param,
      :contactability=>contactability,
#      :lat_rad=>lat_radians, :lng_rad=>lng_radians, 
      :cp_score=>cp_score,
#      :location_hash=>geohash, 
#      :location=>"#{lat},#{lng}",
      :category_ids=>solr_category_ids, :relationship_ids=>solr_first_degree_ids
    }
  end
  
  def contactability
    return 50 if user_id
    c=0
    c+=1 if phone
    c+=5 if fax
    c+=4 if url.present?
    c+=4 if crawl_emails.present?
    c+=5 if other_emails.present?
    c+=20 if email
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
    self.cp_score = 0
    self.cp_score += relationships.count
    self.cp_score += testimonials.published.count
    cp_score
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
