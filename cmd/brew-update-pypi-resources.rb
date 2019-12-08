#:  * `update-pypi-resources` FORMULA
#:
#:  Checks for latest releases of python dependencies
#:  specified as resources pulled from pypi.org
#:  and writes updates back to formula.

require "json"
require "net/http"

module Homebrew
  module_function

  def name_and_version_from_url(url)
    match = url.match(%r{https://files.pythonhosted.org/packages/.*/(.*)-(.*).tar.gz$})
    name = match[1]
    version = match[2]
    [name, version]
  end

  def latest_url_and_checksum(name)
    uri = URI("https://pypi.org/pypi/#{name}/json")
    json = Net::HTTP.get(uri)
    hash = JSON.parse(json)
    sha256 = hash["urls"].last["digests"]["sha256"]
    url = hash["urls"].last["url"]
    [url, sha256]
  end

  exit if ARGV.empty?

  formula = ARGV.formulae.last
  formula.resources.each do |resource|
    next if resource.name == "homebrew-virtualenv"

    name, version = name_and_version_from_url(resource.url)
    url, checksum = latest_url_and_checksum(name)
    name, version_latest = name_and_version_from_url(url)

    next if version == version_latest

    ohai "#{name} : #{version} -> #{version_latest}"

    content = File.read(formula.path)
    content.gsub!(/#{resource.url}/, url)
    content.gsub!(/#{resource.checksum}/, checksum)
    File.open(formula.path, "w") { |file| file.write(content) }
  end
end
