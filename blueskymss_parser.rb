require 'mechanize'
require 'json'
require 'ox'

class BlueskymssParser
  TOKEN_QUERY = 'client_id=247medstaff&application_key=9E9E914F397943A8989763538EF67025&grant_type=password'
  TOKEN_URL = 'https://bssservice.blueskymss.com/auth/token'
  LIST_URL = "https://api.blueskymss.com/api/Needs/list"
  DETAILS_URL = "https://api.blueskymss.com/api/Needs/jobDetails"
  SITE_URL = "https://jobboard.blueskymss.com/JobBoard/jobBoard.html?a=247medstaff&it=3&s=1&bss=2&c=1&fv=111&fc=1#"
  DATE_FROM = '01/05/2022'
  DATE_TO = '01/30/2023'

  def generate_xml(path)
    doc = Ox::Document.new(:version => '1.0')
    jobs = get_jobs
    jobs_count = jobs.nodes.count
    source = Ox::Element.new('source')
    source << (Ox::Element.new('jobs_count') << jobs_count.to_s)
    source << (Ox::Element.new('generation_time') << Time.now.utc.strftime('%m/%d/%Y %H:%M %p'))
    source << jobs
    doc << source
    xml = Ox.dump(doc)
    File.write(path + '//file.xml', xml, mode: 'w')
  end

  private

  def get_jobs
    jobs = Ox::Element.new('jobs')
    @mechanize = Mechanize.new

    info = @mechanize.post(TOKEN_URL,
                           TOKEN_QUERY, {
                             'Content-Type' => 'application/json; charset=UTF-8'
                           })
    token = JSON.parse(info.content)["access_token"]
    info = @mechanize.post(LIST_URL,
                           generate_query(0, DATE_FROM, DATE_TO), {
                             'Content-Type' => 'application/json; charset=UTF-8',
                             "authorization" => "Bearer " + token
                           })
    count = JSON.parse(info.content)["count"]
    info = @mechanize.post(LIST_URL,
                           generate_query(count, DATE_FROM, DATE_TO), {
                             'Content-Type' => 'application/json; charset=UTF-8',
                             "authorization" => "Bearer " + token
                           })
    parameters_rows = JSON.parse(info.content)["rows"]
    parameters_rows.each do |parameters_row|
      jobs << parse_job(token, parameters_row)
    end
    jobs
  end

  def parse_job(token, parameters_row)
    job_query = "[{
       'key':'id',
       'value':'#{parameters_row["Id"]}'
      },{
        'key':'type',
        'value':'#{parameters_row["Type"]}'
    }]"
    info = @mechanize.post(DETAILS_URL,
                           job_query, {
                             'Content-Type' => 'application/json; charset=UTF-8',
                             "authorization" => "Bearer " + token
                           })
    detail_hash = JSON.parse(info.content)["rows"][0]
    detail_parameters = Hash(title: detail_hash["Degree"],
                             url: SITE_URL,
                             job_reference: parameters_row["Id"],
                             city: detail_hash["City"],
                             state: detail_hash["State"],
                             location: "#{detail_hash["City"]}, #{detail_hash["State"]}",
                             body: detail_hash["Job Descriptions"],
                             pay_rate: detail_hash["Pay Rate"],
                             start_date: detail_hash["Start Date"],
                             duration: detail_hash["Duration"])
    job = Ox::Element.new('job')
    detail_parameters.keys.each do |key|
      job << (Ox::Element.new(key) << detail_parameters[key])
    end
    job
  end

  def generate_query(count, date_from, date_to)
    "[{
       'key':'type',
       'value':'2'
    }, {
       'key':'ShowType',
       'value':'1'
    }, {
       'key':'c0',
       'value':'DateFrom = #{date_from}'
    }, {
       'key':'c1',
       'value':'DateTo = #{date_to}'
    }, {
       'key':'columns',
       'value':'Id,StartDate,Duration,TypeName,City,StateID,Description,Details'
    }, {
       'key':'pageCount',
       'value':'true'
    }, {
       'key':'pageNumber',
       'value':1
    }, {
       'key':'pageSize',
       'value':#{count}
    }, {
       'key':'reqInd',
       'value':1
    }]"
  end
end