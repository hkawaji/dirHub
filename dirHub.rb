#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'cgi'
require 'uri'
require 'open-uri'
require 'optparse'

#
# for Hub / Tracks
#

module TrackHubUtil

  Track_type_suffix = [".bb", ".bw", ".st", ".cp", ".mw"]

  def get_trackDb( array , override_attr = {} , indent = 0 , user_attr = {})
    str = ""
    array.each do |ctt|
      t = create_track( ctt, override_attr , indent , user_attr )
      next if t == "non track"
      str += t.trackLines + "\n\n"
    end
    return str
  end


  def create_track( hash , override_attr = {} , indent = 0, user_attr = {})
    suffix = File.extname( hash["path"] )
    if Track_type_suffix.include?(suffix)
      str = sprintf( "Track%s", suffix.sub(".","").capitalize )
      cls = eval str
      return cls.new( hash , override_attr , indent , user_attr )
    else
      return "non track"
    end
  end

  module_function :create_track
end



class Hub
  include TrackHubUtil
  attr_accessor :conf , :base_dir , :lines , :user_attr


  def initialize( hash , user_attr = {} )
    @conf = hash
    @base_dir = "."
    @lines = {
      :hub => "test", :shortLabel => "test", :longLabel => "test",
      :genomesFile => "genomes.txt", :email => "test@example.com"
    }
    @user_attr = user_attr
    override_with_user_attr
  end


  def override_with_user_attr
    if @user_attr.has_key?("Hub") then
      @user_attr["Hub"].keys.each do |str|
        if @lines.has_key?(str.to_sym) then
          @lines[str.to_sym] = @user_attr["Hub"][str]
        end
      end
    end
  end


  def print_hub( dry_run = false ) 
    str = "\n"
    @lines.keys.each{|k| str += k.to_s + " " + @lines[k] + "\n"}
    if ( dry_run == false ) then
      File.open("#{@base_dir}/hub.txt","w"){|ofh| ofh.puts str}
    end
    return str
  end 


  def print_genomes( dry_run = false )
    trackdb_files = print_trackDb( true )
    str = "\n"
    trackdb_files.keys.each do |f|
      str += sprintf("genome %s\ntrackDb %s\n", trackdb_files[f][:assembly], f )
    end

    if ( dry_run == false ) then
      File.open("#{@base_dir}/genomes.txt","w"){|ofh| ofh.puts str}
    end
    return str
  end


  def print_trackDb( dry_run = false )
    trackdb_files = {}

    @conf["contents"].each do |ctt|
      next if ctt["contents"].class != Array
      next if ctt["contents"].length == 0

      str = get_trackDb( ctt["contents"] , {} , 0 , @user_attr )
      g = File.basename( ctt["path"] )
      trackdb_file = sprintf("%s_trackDb.txt", g)

      if ( dry_run == false ) then
        File.open("#{@base_dir}/#{trackdb_file}", "w") do |ofh|
          ofh.puts str.gsub("%","%25")
        end
      end

      trackdb_files[ trackdb_file ] = { :assembly => g, :content => str }
    end
    return trackdb_files
  end


end


class Track
  include TrackHubUtil
  attr_accessor :conf , :lines , :override_attr , :indent , :user_attr
 
  def initialize( hash , override_attr = {} , indent = 0, user_attr = {} )
    @conf = hash
    @override_attr = override_attr
    @indent = indent
    @user_attr = user_attr
  end


  def trackLines
    _init_lines
    _extra_lines
    _override_lines
    _override_with_user_attr
    _trackLines + _trackLines_children
  end


  def _init_lines
    tn = @conf["path"].split(/\//).select{|t|
      suffix = File.extname( t )
      TrackHubUtil::Track_type_suffix.include?(suffix)
    }.join("|")

    tn_no_suffix = @conf["path"].split(/\//).select{|t|
      suffix = File.extname( t )
      TrackHubUtil::Track_type_suffix.include?(suffix)
    }.collect{|t|
      suffix = File.extname( t )
      File.basename( t, suffix )
    }.join("_")

    suffix = File.extname( @conf["path"] )
    sl = URI.unescape( File.basename( @conf["path"] , suffix ) )
    ll = URI.unescape( tn_no_suffix )
    @lines = { :track => tn, :shortLabel => sl, :longLabel => ll }
  end


  def _extra_lines
  end


  def _override_lines
    override_attr.keys.each do |k|
      @lines[k] = override_attr[k]
    end
  end


  def _override_with_user_attr

    if @user_attr.has_key?( self.class.to_s ) then
      buf = @user_attr[ self.class.to_s ]
      buf.keys.each do |str|
        @lines[str.to_sym] = buf[str].to_s
      end
    end

    if @user_attr.has_key?( "TrackName" ) then
      if @user_attr[ "TrackName" ].has_key?( @lines[:track] ) then
        buf = @user_attr[ "TrackName" ][ @lines[:track] ]
        buf.keys.each do |str|
          @lines[str.to_sym] = buf[str].to_s
        end
      end
    end

  end


  def _trackLines
    str = "\n"
    idt = "\t" * indent
    @lines.keys.each{|k| str += idt + k.to_s + " " + @lines[k] + "\n"}
    return str
  end


  def _trackLines_children
    return ""
  end

end


class TrackBw < Track
  def _extra_lines
    @lines[:type] = "bigWig"
    @lines[:bigDataUrl] = @conf["path"]
    @lines[:autoScale] = "on"
    if @override_attr.has_key?(:parent)
      tmp = @override_attr[:parent] + "|" + @override_attr[:parent].split(/\|/).last
      @lines[:color] = "255,0,0" if @lines[:track] == tmp + ".fwd"
      @lines[:color] = "0,0,255" if @lines[:track] == tmp + ".rev"
    end
  end
end


class TrackBb < Track
  def _extra_lines
    @lines[:type] = "bigBed"
    @lines[:bigDataUrl] = @conf["path"]
  end
end


class TrackSt < Track
  def _extra_lines
    @lines[:superTrack] = "on"
  end


  def _trackLines_children
    return "" unless @conf.keys.include?("contents")
    get_trackDb(
      @conf["contents"] ,
      { :parent => @lines[:track] },
      @indent + 1,
      @user_attr
    )
  end
end


class TrackCp < Track
  def _extra_lines
    return "" unless @conf.keys.include?("contents")
    a_child = create_track( @conf["contents"][0] , {} , 0 , @user_attr )
    a_child.trackLines
    @lines[:type] = a_child.lines[:type]
    @lines[:compositeTrack] = "on"
  end


  def _trackLines_children
    return "" unless @conf.keys.include?("contents")
    get_trackDb(
      @conf["contents"] ,
      { :parent => @lines[:track] + " on" },
      @indent + 1,
      @user_attr
    )
  end
end


class TrackMw < Track
  def _extra_lines
    @lines[:container] = "multiWig"
    @lines[:type] = "bigWig"
    @lines[:aggregate] = "transparentOverlay"
    @lines[:showSubtrackColorOnUi] = "on"
  end


  def _trackLines_children
    return "" unless @conf.keys.include?("contents")
    get_trackDb(
      @conf["contents"] ,
      { :parent => @lines[:track] },
      @indent + 1,
      @user_attr
    )
  end
end


#
# retrival of target files
#

module TrackFiles

  def self.retrieve_from_dir(path)
    files = Dir.entries(path)

    contents = []
    files.sort.each do |infile|
      next if infile == "." or infile == ".."
      infile = path + "/" + infile
      ft = File::ftype(infile)
      case ft
      when "directory"
        contents << retrieve_from_dir(infile)
      when "file" , "link"
        suffix = File.extname( infile )
        if TrackHubUtil::Track_type_suffix.include?(suffix)
          contents << { "path" => infile }
        end
      else
        STDERR.puts "Warning: not processed file, '#{ft}' type #{infile} "
      end

    end
    return { "path" => path, "contents" => contents }
  end


  def self.retrieve_from_url(url)
    html = ""
    begin
      OpenURI.open_uri(url){|ofh| html = ofh.read }
    rescue => e
      puts e
      return
    end

    files = html.scan(/href=\"([^\"]+)\"/).
      collect{|o| o[0] }.
      select{|o| ! o.start_with?("?")  }.
      select{|o| ! o.start_with?(".")  }.
      select{|o| ! o.match(":\/\/")  }.
      select{|o| ! o.start_with?("/")  }

    url = url + "/" unless url.end_with?("/")
    contents = []
    files.sort.each do |infile|
      if infile.end_with?("/") then
        contents << retrieve_from_url(url + infile)
      elsif infile.match(/.bw$|.bb$/) then
        contents << { "path" => url + infile }
      else
        STDERR.puts "Warning: unprocessed file #{infile}"
      end
    end
    return { "path" => url, "contents" => contents }
  end


  def self.retrieve( obj )
    if File.exist?( obj )
      ft = File::ftype( obj )
      return retrieve_from_dir(obj) if ft == "directory"
    else
      return retrieve_from_url(obj) unless File.exist?( obj )
    end

    return nil
  end


  def self.save( contents, outfile )
    return if outfile == "FALSE"
    ofh = File.open( outfile , "w")
      ofh.puts contents.to_yaml if outfile.match(/.yaml$/)
      ofh.puts JSON.pretty_generate( contents ) if outfile.match(/.json$/)
    ofh.close
  end

end


module UserSpecifiedAttr

  def self.retrieve_content( infile )
    str = ""
    if File.exist?( infile )
      File.open( infile ){|ifh| str = ifh.read }
    else
      begin
       OpenURI.open_uri(infile){|ifh| str = ifh.read}
      rescue => e
       puts e # error
      end
    end
    str
  end


  def self.load( infile )
    case infile
    when /.*\.[yaml|yml]/
      str = retrieve_content(infile)
      return {} if str == ""
      return YAML.load(str)
    when /.*\.[json|jsn]/
      str = retrieve_content(infile)
      return {} if str == ""
      return JSON.load(str)
    else
      return {}
    end
  end

end



def exit_with_readme

  print <<-EOF

dth (DTH, Directory-to-TrackHub)
==================================

Generate a set of configuration files for track hub (hub.txt, genomes.txt, and ${genome}_trackDb.txt) based on a directory structure.


Options
-------

To be written.


Compatibility
-------------

[Ruby][] is required to run this script. The resulting config is compatible with [Hub Track Database Definition (v2)][], in particular the following track types (suffix recognized):

* bigWig (bw)
* bigBed (bb)
* super track (st)
* composite track (cp)
* multiWig (mw)

but not the track types below yet:

* bigBarChart
* bigChain
* bigGenePred
* bigNarrowPeak
* bigMaf
* bigPsl
* bam
* cram
* halSnake
* vcfTabix


Directory structure mapping to track hub
----------------------------------------

track hub is a framework to display user-specified genomic data in genome browsers. It requires data files (such as bigWig and bigBed) accessible over http/https with a set of configuration files. This tool generates the configuration files based on a directory containing the data files structured as follows:

* a directory placed in the top level represents the genome assembly
* suffix of a file or directory represents the track type
* a sub-directory represents 'grouping' tracks, such as supertrack

For example, this directory structure can be converted to track hub:

 ./hg19/
    test.st/
      signal1.bw
      signal2.bw
      peaks.cp/
        peak1.bb
        peak2.bb


User-specified directory structure
----------------------------------

The directory structure can be specified in the following ways:

* local directory (path to the directory)
* remote directory (URL to the directory)
* directory structure (YAML or JSON file)

Specification of the remote directory is possible only when directory listing enabled.

Directory structure file has to be organized like this:

{ "path" :  $filePath   , "contents" : $filePath}




User-specified track attributes
-------------------------------

Track attributes can be added or overwritten according to the user specification in YAML or JSON, since only minimum attributes are set for each track as default. The attributes has to be stored as hash, as:

{
  "hub" : {} ,
  "genomes" : {} ,
  "trackType" : {} ,
  "trackName" : {}
}


Examples
--------

To be written.


Reference
---------

[Ruby]: http://ruby-lang.org
[Hub Track Database Definition (v2)]: https://genome.ucsc.edu/goldenpath/help/trackDb/trackDbHub.html

Author, copyright, and license
------------------------------

This software is written by Hideya Kawaji.
Copyright (c) 2017 RIKEN.
Distributed under BSD License.



  EOF
  exit
end



def mywebapp(port)
  require 'sinatra'

  set :port , port
  set :protection, :except => :path_traversal

  helpers do

    def prep( hbase, hattr = "FALSE") # this can handle https as well as http
      #hbase.sub!(":/","://")
      #hattr.sub!(":/","://")
      hbase = URI.decode(hbase)
      hattr = URI.decode(hattr)
      contents = TrackFiles.retrieve( hbase )
      user_attr = UserSpecifiedAttr.load( hattr )
      Hub.new( contents , user_attr )
    end


    def body_text( hub, outfile )
      content_type 'text/plain'

      case outfile
      when "hub.txt"
        hub.print_hub( dry_run = true )
      when "genomes.txt"
        hub.print_genomes( dry_run = true )
      when /\w+_trackDb.txt/
        tdb = hub.print_trackDb( dry_run = true )
        if tdb.has_key?( outfile ) then
          tdb[ outfile ][:content] if tdb.has_key?( outfile )
        else
          nil
        end
      end
    end

  end


  get %r{/(http.+)/(http.+)/(\w+\.txt)} do |hbase,hattr,outfile|
    hub = prep( hbase, hattr )
    body_text( hub, outfile )
  end


  get %r{/(http.+)/(\w+\.txt)} do |hbase,outfile|
    hattr = hbase + "%2Fd2th.yaml"
    hub = prep( hbase , hattr)
    body_text( hub, outfile )
  end

  post %r{/.*} do
    @params[ :url ] = "" unless @params.has_key?(:url)

    if @params.has_key?( :attr ) && @params[ :attr ] != ""
      @params[ :hub_url ] = "./" +
        CGI.escape( params[:url] ) + "/" + 
        CGI.escape( params[:attr] ) + "/hub.txt"
    else
      @params[ :hub_url ] = "./" + CGI.escape( params[:url] ) + "/hub.txt"
    end

    erb :index
  end

  get %r{/.*} do
    erb :index
  end

end


###
### main
###

params = ARGV.getopts(
  '',
  'readme',
  'webapp',
  'port:4567'  ,
  'input-trackfiles:.',
  'user-attr:FALSE',
  'output-trackfiles:FALSE',
  'output-config-dir:FALSE',
  'output-stdout-type:FALSE'
)

# readme
exit_with_readme if params["readme"]

# web app.
if params["webapp"] then
  mywebapp ( params["port"] )
end



# retrieve contents
contents = TrackFiles.retrieve( params["input-trackfiles"] )

# save contents (if required)
TrackFiles.save( contents, params["output-trackfiles"] )

# load user-specified parameters
user_attr = UserSpecifiedAttr.load( params["user-attr"] )

# set up Hub object
hub = Hub.new( contents , user_attr )

# print hub config files to stdout
case params["output-stdout-type"]
when "hub.txt"
  STDOUT.puts hub.print_hub( dry_run = true )
when "genomes.txt"
  STDOUT.puts hub.print_genomes( dry_run = true )
else
  tdb = hub.print_trackDb( dry_run = true )
  if tdb.has_key?( params["output-stdout-type"] ) then
    STDOUT.puts tdb[ params["output-stdout-type"] ][:content]
  end
end


# print hub config files under dir

if ( ( params["output-config-dir"] != "FALSE"     ) &&
     ( File.exist?( params["output-config-dir"] ) ) ) then
  ft = File::ftype( params["output-config-dir"] )
  if ft == "directory" then
    hub.base_dir = params["output-config-dir"]
    hub.print_hub
    hub.print_genomes
    hub.print_trackDb
  end
end



