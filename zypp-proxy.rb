require 'rubygems'
require 'net/http'
require 'thin'
require 'xmlsimple'


class SimpleAdapter
  def call(env)
    [ 200, { 'Content-Type' => 'text/plain' }, ["hello!\n #{env.to_s}"] ]
  end
end



class ForwardAdapter

  def initialize(offset, host, port)
    @offset = offset
    @host = host
    @port = port
    puts "FWD-INIT offs: #{offset}"
    puts "FWD-INIT host: #{host}"
    puts "FWD-INIT port: #{port}"
  end


  def get_or_follow_http(host, port, path)
    res_code = 0
    loop_count = 0
    res = Net::HTTP.new('')

    while ( [0, 301, 302, 303, 307].include?(res_code)  &&  loop_count < 12 )
      loop_count += 1
      req = Net::HTTP::Get.new(path)
      res = Net::HTTP.start( host, port) { |http|  http.request(req) }

      if res.header['location']
        host = URI.parse(res.header['location']).host
        port = URI.parse(res.header['location']).port
        path = URI.parse(res.header['location']).path
      end

      #res.each {|k, v| puts "#{k}  :  #{v}" }
      res_code = res.code.to_i || 0
      puts "<<--CODE #{res_code}-->> "
    end
    res

  end



  def call(env)
    puts "-"*30
    orig_req = Rack::Request.new(env)
    #env.each {|k, v| puts "#{k}  :  #{v}" } if env

    path = orig_req.path.sub(@offset, '')
    path = '/' if path == ''
    #puts "  OFFSET:  " + @offset + "  :::  OLD PATH #{orig_req.path}" + "  :::  NEW PATH #{path}"

    res = get_or_follow_http( @host, @port, path )

    # TODO: cache the delivered files locally and deliver them if they are equal

    #res.each {|k, v| puts "#{k}  :  #{v}" }
    #puts "CODE: #{res.code}"

    [ res.code.to_i, { 'Content-Type' => res.content_type }, [ res.body ] ]
  end
end


class RepoIndexAdapter

  def call(env)
    orig_req = Rack::Request.new(env)

    # TODO: read repos.d/files and create the repoindex.xml dynamically

    res_body1 = '<repoindex> </repoindex>'
    res_body = XmlSimple.xml_out(REPOS, { 'RootName' => 'repoindex' } )
    [ 200, { 'Content-Type' => 'text/xml' }, [ res_body ] ]
  end

end


REPOS ={ 'repo' => [
          { 'name' => 'openSUSE-11.1-Update',
            'alias' => 'repo-update',
            'url' => 'http://localhost:3000/update/11.1/',
            'description' => "Foo Bar",
            'priority' => 0,
            'pub' => 0
          },
          { 'name' => 'openSUSE-11.1-Oss',
            'alias' => 'repo-oss',
            'url' => 'http://localhost:3000/distribution/11.1/repo/oss/',
            'description' => "Fara und Foo",
            'priority' => 0,
            'pub' => 0
          }
        ]
     }


# static redirection - later read files in repos.d/ and create URLMap
host = "download.opensuse.org"
port = 80

app = Rack::URLMap.new(
                         '/repo/update' => ForwardAdapter.new('/repo/update', host, port),
                         '/service/repo/repoindex.xml' => RepoIndexAdapter.new()
                        #'/test'  => SimpleAdapter.new,
                        #'/files' => Rack::File.new('.')
                      )


Thin::Server.new('0.0.0.0', 3000, app).start!


=begin
# how to write repoindex.xml
# from SMT:  NU::RepoIndex.pm
$writer->emptyTag('repo',
                  'name' => $catalogName,
                  'alias' => $catalogName,                 # Alias == Name
                  'description' => ${$val}{'DESCRIPTION'},
                  'distro_target' => ${$val}{'TARGET'},
                  'path' => $LocalRepoPath,
                  'priority' => 0,
                  'pub' => 0
                );


=end


=begin
# redirect headers
x-as  :  29298
location  :  http://ftp5.gwdg.de/pub/opensuse/update/11.1/rpm/i686/glibc-2.9-2.3_2.10.1.i686.delta.rpm
content-type  :  text/html; charset=iso-8859-1
server  :  Apache/2.2.11 (Linux/SUSE)
date  :  Wed, 22 Jul 2009 16:46:06 GMT
content-length  :  364
x-mirrorbrain-realm  :  country
x-prefix  :  195.135.220.0/22
x-mirrorbrain-mirror  :  ftp5.gwdg.de
CODE: 302
=end
