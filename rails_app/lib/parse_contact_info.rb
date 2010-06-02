class ParseContactInfo

  class << self
    def to_us_short_phone(str)
      return nil unless str.present?
      s = str.gsub /\D/,''
      return nil unless s.size >=10
      s[0,1]=='1' ? s[1,10] : s[0,10]
    end

    def to_us_phone(str)
      return nil unless str.present?
      s = str.gsub /\D/,''
      return nil unless s.size >=10
      s[0,1]=='1' ? s[0,11] : '1'+s[0,10]
    end

    def to_intl_phone(str)
      return nil unless str.present?
      s = str.gsub /\D/,''
      return nil unless s.size >=6
      s
    end

    def to_phone(str,country)
      (country.blank? or country=~/(usa|united states of america|united states|canada)/i) ? to_us_phone(str) : to_intl_phone(str)
    end
    
    def to_plain_email(str)
      return nil if str.blank?
      addr = TMail::Address.parse(str).address rescue (return(nil))
      addr.is_email? ? addr : nil
    end
    
    def countries_and_alternate_names
      ['Republic of Korea', 'South Korea', 'United States of America', 'The Philippines']+ActionView::Helpers::FormOptionsHelper::COUNTRIES + ['Russia', 'US', 'USA', 'U.S.A', 'England', 'UK', 'U.K.', 'Iran', 'Taiwan','Korea','Tanzania','Macedonia','PR']
    end
  end
  
  @@state_regexp_upcase = Regexp.new '\b('+::US_STATES.collect{|t| t[1]}.join('|')+')\b'
  @@state_regexp_anycase = Regexp.new '\b('+::US_STATES.collect{|t| t[1]}.join('|')+')\b', Regexp::IGNORECASE
  @@full_state_regexp_upcase = Regexp.new '\b('+::US_STATES.collect{|t| t[0]}.join('|')+')\b'
  @@full_state_regexp_anycase = Regexp.new '\b('+::US_STATES.collect{|t| t[0]}.join('|')+')\b', Regexp::IGNORECASE
  @@ends_with_country = Regexp.new('\b('+countries_and_alternate_names.join('|').gsub('(','\(').gsub(')','\)').gsub('.','\.')+')\s*\Z',
                                    Regexp::IGNORECASE)
  @@us_zip = /\b(\d{5}(?:-\d{4})?)\b/

  class << self

    def parse_address_last_line(str, debug=false)
      return nil if str.blank?
      orig_str=str
      str=str.dup
      country=zip=city=state=full_state=nil
      if s=str.match(@@ends_with_country)
        country = s[1]
        str.sub!(s[1],'')
        puts("==============country: #{country}") if debug
      end
      if z=str.match(@@us_zip)
        zip = z[1]
        str.sub!(z[1],'')
      elsif debug
        puts "no zip: #{str}" if debug
      end
      if s = str.match(@@full_state_regexp_upcase)
        full_state = s[1]
        state = to_state(s[1])
        str.sub!(s[1],'')
      elsif s = str.match(@@full_state_regexp_anycase)
        full_state = s[1]
        state = to_state(s[1])
        str.sub!(s[1],'')
      elsif s = str.match(@@state_regexp_upcase)
        state = s[1]
        full_state = to_state(s[1])
        str.sub!(s[1],'')
      elsif s = str.match(@@state_regexp_anycase)
        state = s[1]
        full_state = to_state(s[1])
        str.sub!(s[1],'')
      elsif debug
        puts "no state: #{str}" if debug
      end
      if state.blank? and zip.blank? and str.present? and str.strip.size > 2
        city=str.sub(/\s*,\s*/,'')
        puts "zzzzzzzzzzzzzzzzzzz #{orig_str} zzzzzzzzzzzzzz  default city: #{city}" if debug
      end
      [city,state,full_state,zip,country]
    end

    # Convert a short state to a long state and vice versa
    def to_state(str)
      return nil if str.blank?
      if str.size==2
        ::US_STATES.detect{|s| s[1].downcase==str.downcase}[0] rescue nil
      else
        ::US_STATES.detect{|s| s[0].downcase==str.downcase}[1] rescue nil
      end
    end

  end
end
