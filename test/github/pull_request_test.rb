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

  def test_regular_title
    ['The commit', 'The original commit'].each do |title|
      pr = pull_request(nil, {'title' => title})
      refute pr.cherry_pick?, title
    end
  end

  def test_cherry_pick_is_cherry_pick
    ['CP: This is a cherry-pick', '[CP] This was cherry-picked', 'Cherry picks for 3.7'].each do |title|
      pr = pull_request(nil, {'title' => title})
      assert pr.cherry_pick?, title
    end
  end

  def test_cherry_pick_is_not_cherry_pick
    ['This CP commit is not a CP', 'This is not a [CP] cherry-picked'].each do |title|
      pr = pull_request(nil, {'title' => title})
      refute pr.cherry_pick?, title
    end
  end

  def test_get_branch_labels
    pr = pull_request

    mapping = {
      'master'    => 'full',
      'ma.+'      => 'regex',
      ''          => 'empty',
      'unmatched' => 'non-matching',
    }

    assert_equal(pr.get_branch_labels(mapping), ['full', 'regex'])
  end

  private

  def pull_request(repo=nil, raw_data=nil, client=nil)
    repo ||= OpenStruct.new(full_name: 'theforeman/test', redmine_project: 'test')

    data = {
      'title'  => 'The title',
      'number' => 1234,
      'base'   => {
        'ref' => 'master',
      },
    }
    data.merge!(raw_data) if raw_data

    unless client
      client = Minitest::Mock.new
      client.expect :pull_commits, [], [repo.full_name, data['number']]
    end

    PullRequest.new(repo, data, client)
  end
end
