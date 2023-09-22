require "minitest/autorun"
require 'ostruct'

require 'github/pull_request'

class TestPullRequest < Minitest::Test
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

  def test_get_desired_labels
    pr = pull_request

    mapping = {
      'app/assets2' => 'ui',
      'job_templates' => 'Remote execution',
      'packages-lock.json' => 'packages',
      'partition_tables_templates' => 'Provisioning',
      'provisioning_templates' => 'Provisioning',
    }

    files = pull_files(['job_templates2/', 'app/job_templates/tmplt.erb', 'app/'])
    assert_equal [], pr.get_desired_labels(files, mapping)

    files = pull_files(['job_templates/', 'provisioning_templates/p.erb'])
    assert_equal ['Remote execution', 'Provisioning'], pr.get_desired_labels(files, mapping)

    files = pull_files(['partition_tables_templates/pt.erb', 'provisioning_templates/p.erb'])
    assert_equal ['Provisioning'], pr.get_desired_labels(files, mapping)

    files = pull_files(['packages-lock.json'])
    assert_equal ['packages'], pr.get_desired_labels(files, mapping)
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

  def pull_files(file_paths)
    file_paths.map do |fp| 
      gh_file = Minitest::Mock.new
      gh_file.expect :filename, fp
    end
  end
end
