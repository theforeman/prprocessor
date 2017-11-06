require "minitest/autorun"
require 'ostruct'

require 'github/pull_request'

class TestPullRequest < Minitest::Test
  def test_wip_regular_title
    ['My change', 'Change WIP handling'].each do |title|
      pr = pull_request(nil, {'title' => title})
      refute pr.wip?, title
    end
  end

  def test_wip_is_wip
    ['WIP: This is in progress', '[WIP] still not done'].each do |title|
      pr = pull_request(nil, {'title' => title})
      assert pr.wip?, title
    end
  end

  private

  def pull_request(repo=nil, raw_data=nil, client=nil)
    repo ||= OpenStruct.new(full_name: 'theforeman/test', redmine_project: 'test')

    data = {
      'title'  => 'The title',
      'number' => 1234,
    }
    data.merge!(raw_data) if raw_data

    unless client
      client = Minitest::Mock.new
      client.expect :pull_commits, [], [repo.full_name, data['number']]
    end

    PullRequest.new(repo, data, client)
  end
end
