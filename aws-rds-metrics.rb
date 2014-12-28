#! /usr/bin/env ruby
#
# aws-rds-metrics
#
# DESCRIPTION:
#   Fetch Amazon RDS metrics from CloudWatch
#
# OUTPUT:
#   metric-data
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# LICENSE:
#   Copyright 2014 Hiromitsu Ito
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/metric/cli'
require 'aws-sdk'

class AwsRDSMetrics < Sensu::Plugin::Metric::CLI::Graphite
  option :aws_access_key,
         description: "AWS Access Key. Either set ENV['AWS_ACCESS_KEY_ID'] or provide it as an option",
         short: '-a AWS_ACCESS_KEY',
         long: '--aws-access-key AWS_ACCESS_KEY',
         required: true

  option :aws_secret_access_key,
         description: "AWS Secret Access Key. Either set ENV['AWS_SECRET_ACCESS_KEY'] or provide it as an option",
         short: '-k AWS_SECRET_ACCESS_KEY',
         long: '--aws-secret-access-key AWS_SECRET_ACCESS_KEY',
         required: true

  option :aws_region,
         description: 'AWS Region (such as us-east-1).',
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         default: 'us-east-1'

  option :dbinstanceidentifier,
         description: 'RDS Instance Identifier',
         short: '-i DB_INSTANCE_IDENTIFIER',
         long: '--instance_id DB_INSTANCE_IDENTIFIER',
         required: true

  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: ''

  option :fetch_age,
         description: 'How long ago to fetch metrics for',
         short: '-f AGE',
         long: '--fetch_age',
         default: 60,
         proc: proc(&:to_i)

  option :statistics_type,
         description: "Statics type 'average' or 'minimum' or 'maximum'",
         short: '-t STATISTICS_TYPE',
         long: '--statistics_type',
         default: 'average'

  def run
    if config[:scheme] == ''
      graphitepath = "#{config[:dbinstanceidentifier]}"
    else
      graphitepath = config[:scheme]
    end

    metrics = {
        'BinLogDiskUsage' => 'Bytes',
        'CPUUtilization' => 'Percent',
        'DatabaseConnections' => 'Count',
        'DiskQueueDepth' => 'Count',
        'FreeStorageSpace' => 'Bytes',
        'FreeableMemory' => 'Bytes',
        'NetworkReceiveThroughput' => 'Bytes',
        'NetworkTransmitThroughput' => 'Bytes',
        'ReadIOPS' => 'Count/Second',
        'ReadLatency' => 'Seconds',
        'ReadThroughput' => 'Bytes/Second',
        'ReplicaLag' => 'Seconds',
        'SwapUsage' => 'Bytes',
        'WriteIOPS' => 'Count/Second',
        'WriteLatency' => 'Seconds',
        'WriteThroughput' => 'Bytes/Second'
    }

    stat_type = {
        'average' => 'Average',
        'minimum' => 'Minimum',
        'maximum' => 'Maximum',
        'samplecount' => 'SampleCount',
        'sum' => 'Sum'
    }

    begin

      AWS.config(
        access_key_id: config[:aws_access_key],
        secret_access_key: config[:aws_secret_access_key],
        region: config[:aws_region]
      )
      cloud_watch = AWS::CloudWatch::Client.new

      end_time = Time.now - config[:fetch_age]
      start_time = end_time - 120

      # define all options
      options = {
        'namespace' => 'AWS/RDS',
        'metric_name' => config[:metric],
        'dimensions' => [
          { 'name' => 'DBInstanceIdentifier', 'value' => config[:dbinstanceidentifier] }
        ],
        'start_time' => start_time.iso8601,
        'end_time' => end_time.iso8601,
        'period' => 60,
        'statistics' => [stat_type[config[:statistics_type].downcase]]
      }

      result = {}

      # Fetch all metrics by elasticachetype (redis or memcached).
      metrics.each do |m|
        options['metric_name'] = m[0] # override metric
        resp = cloud_watch.get_metric_statistics(options)
        result[m[0]] = resp[:datapoints][0] unless resp[:datapoints][0].nil?
      end

      unless result.nil?
        result.each do |name, d|
          # We only return data when we have some to return
          output graphitepath + '.' + name.downcase, d[:average], d[:timestamp].to_i
        end
      end
    rescue => e
      puts "Error: exception: #{e}"
      critical
    end
    ok
  end
end
