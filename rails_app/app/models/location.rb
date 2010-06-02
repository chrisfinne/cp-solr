# MyISAM table from US census data. If we need a different solution, look at http://geonames.org/
# klass: M= Military, P=Post Office Boxes, U=Unique ZIP
# Zip codes are NOT unique as we are putting aliases in there (e.g. Bay Area, Peninusula, Manhattan, etc.)
class Location < ActiveRecord::Base
  include FindWithin

  named_scope :california, :conditions=>'state="CA"'
  
  if RAILS_ENV=='test'
    # No need to put the whole table into a YAML just to run a few tests
    establish_connection "development"
  end

  include Geocode

  # Geocode required method
  def full_address
    "#{city} #{full_state} #{zip}".strip
  end
  
  # Geocode required method
  def full_address_changed?
    zip_changed? or city_changed? or state_changed?
  end
  
  cattr_accessor :states, :full_states, :states_downcase, :full_states_downcase, :standard_url_regexp
  
  self.states = ::US_STATES.collect{|s| s[1]}
  self.states_downcase = states.collect{|s| s.downcase}
  self.full_states = ::US_STATES.collect{|s| s[0]}
  self.full_states_downcase = full_states.collect{|s| s.downcase}

  self.standard_url_regexp=Regexp.new('\A([a-z \-]+)-('+states_downcase.join('|')+')-('+full_states_downcase.join('|').gsub(' ','-')+')',Regexp::IGNORECASE)

  # Convert a short state to a long state and vice versa
  def self.to_state(str)
    return nil if str.blank?
    if str.size==2
      ::US_STATES.detect{|s| s[1].downcase==str.downcase}[0] rescue nil
    else
      ::US_STATES.detect{|s| s[0].downcase==str.downcase}[1] rescue nil
    end
  end

  # Assumes its input is from url parameters that are separated by dashes - and it is lowercase
  # Preferred URL Formats in order of eval:
  # /city-state-full-state
  # /2-letter state
  # /zip code
  # /full_state
  # /city (or area), e.g. silicon-valley , tri-state-area , bay-area , manhattan
  # /city-state
  # /whatever-zip
  
  # /city-state-full-state
  # /city-state-full-state-zip
  def self.find_by_url(url)
    return nil unless url.present?
    if match=url.match(/(\d{5})\Z/)
      find_by_zip(match[1])
    elsif match=url.match(standard_url_regexp)
      find_by_city_and_state(match[1].gsub('-',' '),match[2])
    end
  end
  
  def self.find_all_fuzzy(str)
    return [] if str.blank?
    str.gsub!('-',' ')
    str.strip!
    return [] unless str.present?

    return find_all_by_state(str)  if is_state?(str)
    return [] if str.size < 3 # if not a state abbreviation, then it isn't anything
    return find_all_by_zip(str) if is_zip?(str)
    return find_all_by_full_state(str) if is_full_state?(str)
    
    # Is it an exact city match?
    city_match = find_all_by_city(str)
    return city_match if city_match.present?

    return [] unless str.include?(' ') # if no spaces, then it is a single word that doesn't match a zip, city, state or full_state
    
    arr=str.split(' ')
    last=arr.pop
    return find_all_by_city_and_state(arr.join(' '),last) if is_state?(last)

    # the last is a ZIP. The city and state are presumably there, but who cares, just find all with the zip
    return find_all_by_zip(last) if is_zip?(last)
    
    []
  end
  
  # palto alto ca california
  
  def self.is_standard_url?(arg)
    if match = arg.match(//i)
      
    end
    arg=arg.split(' ') if arg.is_a?(String)
    full_state = arg.pop
    return false unless is_full_state?(full_state)
    state = arg.pop
    return false unless is_state?(state)
    city=arg.join(' ')
    [city,state,full_state]
  end
  
  def self.is_state?(str)
    str.size==2 and ([str.downcase] & states_downcase).present?
  end
  
  def self.is_full_state?(str)
    ([str.downcase] & full_states_downcase).present?
  end
  
  def self.is_zip?(str)
    str.size==5 and str !~ /\D/
  end
  
  def full_state
    state.present? ? state : full_state
  end
  
  def nice_klass
    case klass
    when 'M' : 'Military'
    when 'P' : 'Post Office Boxes'
    when 'U' : 'Unique ZIP'
    else
      ''
    end
  end
  
  def url_path(include_zip=true)
    str="#{city} #{state} #{full_state}"
    str+=" #{zip}" if include_zip
    clean_url_keywords(str)
  end
  
end
