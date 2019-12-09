#:  * `update-pypi-resources` FORMULA
#:
#:  Checks for latest releases of python dependencies
#:  specified as resources pulled from pypi.org
#:  and writes updates back to formula.
#:
#:      -n, --dry-run                    Just print updated resources.
#:      -v, --verbose                    Be more specific.

require "json"
require "net/http"
require "optparse"

module Homebrew
  module_function

  def name_and_version_from_url(url)
    match = url&.match(%r{https://files.pythonhosted.org/packages/.*/.*/(.*)-(.*)\.(tar|zip)})
    if match
      name = match[1]
      version = match[2]
      [name, version]
    end
  end

  def latest_url_and_checksum(name)
    uri = URI("https://pypi.org/pypi/#{name}/json")
    json = curl(uri)
    hash = JSON.parse(json)
    hash["urls"]&.reverse_each do |info|
      next unless info["packagetype"] == "sdist"

      return [info["url"], info["digests"]["sha256"]]
    end
  end

  def curl(uri)
    r = Net::HTTP.get_response(uri)
    if r.code == "301"
      uri = URI.parse(r.header["location"])
      curl(uri)
    else
      r.body
    end
  end

  dry_run = false
  verbose = false
  OptionParser.new do |parser|
    parser.on("-n", "--dry-run") { dry_run = true }
    parser.on("-v", "--verbose") { verbose = true }
  end.parse!

  opoo "writing updates back to formula" unless dry_run

  formula = ARGV.formulae.last
  formula&.resources&.each do |resource|
    next if resource.name == "homebrew-virtualenv"

    ohai resource.name

    name, version = name_and_version_from_url(resource.url)
    if !name || !version
      puts "can't parse name or version from url", resource.url if verbose
      next
    end

    url, checksum = latest_url_and_checksum(name)
    if !url || !checksum
      puts "can't find latest url or checksum" if verbose
      next
    end

    name, version_latest = name_and_version_from_url(url)
    if !name || !version
      puts "can't parse name or version from latest url", url if verbose
      next
    end

    if version == version_latest
      puts "already up-to-date" if verbose
      next
    end

    puts "#{version} -> #{version_latest}"

    next if dry_run

    content = File.read(formula.path)
    content.gsub!(/#{resource.url}/, url)
    content.gsub!(/#{resource.checksum}/, checksum)
    File.open(formula.path, "w") { |file| file.write(content) }
  end
end
