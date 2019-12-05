require 'minitest/autorun'
require 'repository'

class TestRepoConfig < Minitest::Test
  def test_path_labels_keys_does_not_contain_trailing_slash
    paths = Repository.all.values
      .select{ |r| r.path_labels? }
      .map{ |r| r.path_labels.keys }
      .flatten
      .select { |file_path| file_path.end_with?('/') }
    assert_equal [], paths, "remove trailing slash from the following paths: #{paths.join(', ')}"
  end
end
