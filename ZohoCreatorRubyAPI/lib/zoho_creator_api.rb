require 'uri'
require 'net/http'
require 'net/https'
require 'rexml/document'
require 'xmlsimple'
include REXML

#
# TODO: Everything.
# Ideas: - Use XPath more instead of xmlsimple.
#        - Generic method to turn result from get_records into simple hash.
#

=begin
Represents a field of type
(({<field name="name" value="value" />}))
=end
class Field 
  def initialize(name, value, operator = nil)
    @field = name
    @operator = operator
    @value = value
  end

  def to_xml_string
    return to_xml_element.to_s
  end
  
  def to_xml_element
    element = Element.new("field")
    element.add_attribute('name', @field)
    element.add_attribute('compOperator', @operator) if @operator
    element.add_attribute('value', @value)
    return element
  end
end

class Criterion
  def initialize
    # <field>, <...?>
    @elements = Array.new
  end
  
=begin
* field - A field or ???
=end
  def add(element)
    @elements << element
    
  end
  
  def to_xml_string
    return to_xml_element.to_s
  end
  
  def to_xml_element
    criteria = Element.new("criteria")
    @elements.each do |c|
      criteria.add_element(c.to_xml_element)
    end
    return criteria
  end
end

class NewValues
  def initialize
    @new_vals = Array.new
  end
  
  def add(field)
    @new_vals << field
  end
  
  def to_xml_element
    new_vals = Element.new("newvalues")
    @new_vals.each do |nv|
      new_vals << nv.to_xml_element
    end
    return new_vals
  end
  
  def to_s
    return to_xml_element.to_s
  end
end

class Range
  def initialize(start_index = 1, limit = 100)
    @start_index = start_index
    @limit = limit
  end
  
  def to_xml_string
    return to_xml_element.to_s
  end
  
  def to_xml_element
    range = Element.new("range")
    range.add_element("startindex").text = @start_index
    range.add_element("limit").text = @limit
    return range
  end
end

class ZohoCreatorAPI
  def initialize(application, login, password, api_key)
     @app_name    = application
     @login       = login
     @password    = password
     @ticket      = nil
     @api_key     = api_key
  end
  
  def login
    host = get_ticket_request_host
    path = get_ticket_request_path
    
    # Hit the server for a token.
    http = Net::HTTP.new(host, 443)
    http.use_ssl = true
    resp = http.get(path, nil)

    # Turn the response into something usable.
    zoho_resp = Hash.new
    resp.body.split("\n").each do |line|
      key, value = line.split("=")
      zoho_resp[key] = value
    end
    
    if(zoho_resp['RESULT'].upcase == "TRUE")
      @ticket = zoho_resp['TICKET']
    else
      raise "Couldn't fetch zoho ticket: #{resp.body}"
    end
  end
  
  public
  
=begin
  DESC: Retuns the value in target_field of the first record that has
        matching_field == matching_value.
  ARGS:
    form_name - The name of the form to search
    target_field - The field whose value we want.
    matching_field - The field to match
    matching_value - The value to match.
=end  
  def get_value(form_name, target_field, matching_field, matching_value)  
    f = Field.new(matching_field, matching_value, "EQUALS")
    c = Criterion.new()
    c.add(f)

    records = get_records(form_name, c)
    value = nil
    
    if(records == nil || records.size == 0)
      raise "ERROR: No records found in '#{form_name}' with '#{matching_field}'=='#{matching_value}'"
    end
    
    records.each do |cur_rec|
      # TODO: Error check this
      value = cur_rec["column"][target_field]["value"][0]
      break
    end
    
    return value
  end
    
  def set_value(form, criterion, new_vals_hash)
    xml_string = ""
    
    new_vals = NewValues.new
    new_vals_hash.each do |k, v|
      new_vals.add(Field.new(k, v))
    end
    
    doc = Document.new
    doc.add_element("ZohoCreator")
    app_list = doc.root.add_element("applicationlist")
    application = app_list.add_element("application", {'name' => @app_name})
    formlist = application.add_element("formlist")
    form = formlist.add_element("form", {'name' => form})
    update = form.add_element("update")
    update.add_element(criterion.to_xml_element)
    update.add_element(new_vals.to_xml_element)

    xml_string = doc.to_s
    res = Net::HTTP.post_form(
      URI.parse(get_write_url),
      {'XMLString' => xml_string}
    )
    res_doc = REXML::Document.new(res.body)

    success_element =  REXML::XPath.first(res_doc.root, '//response/result/form/update/status')
    if(success_element == nil || success_element.text.upcase != "SUCCESS")
      puts "ERROR: Couldn't set value: #{res.body}"
      return false
    else
      return true
    end
  end
  
  def get_records(form_name, criterion, range = Range.new)
    xml_string = ""
    
    doc = Document.new
    doc.add_element("ZohoCreator")
    application = doc.root.add_element("application", {'name' => @app_name})
    form = application.add_element("form", {'name' => form_name})
    
    form.add_element(criterion.to_xml_element)
    form.add_element(range.to_xml_element)

    xml_string = doc.to_s
    # puts xml_string
    res = Net::HTTP.post_form(
      URI.parse(get_read_url),
      {'XMLString' => xml_string}
    )
    
    # Todo: Check status code and array sizes.
    result = XmlSimple.xml_in(res.body, 'KeyAttr' => 'name')
    # Yes, this is actually an array, even though it doesn't look like it from
    # the names and structure Zoho chose for the data.  >:-(
    records =  result["form"][form_name]["records"][0]["record"] 
    return records
  end
  
  
  private
  
  def get_ticket_request_path
    return "/login?servicename=ZohoCreator&FROM_AGENT=true&LOGIN_ID=#{@login}&PASSWORD=#{@password}"
  end
  
  def get_ticket_request_host
    return "accounts.zoho.com";
  end
  
  def get_read_url
    return "http://creator.zoho.com/api/xml/read/apikey=#{@api_key}&ticket=#{@ticket}"
  end
  
  def get_write_url
    return "http://creator.zoho.com/api/xml/write/apikey=#{@api_key}&ticket=#{@ticket}"
  end
end
