class PullRequest

  attr_accessor :raw_data, :title, :issue_numbers

  def initialize(raw_data)
    self.raw_data = raw_data
    self.title = raw_data['title']

    self.issue_numbers = []
    title.scan(/([\s\(\[,-]|^)(fixes|refs)[\s:]+(#\d+([\s,;&]+#\d+)*)(?=[[:punct:]]|\s|<|$)/i) do |match|
      action, refs = match[1].to_s.downcase, match[2]
      next if action.empty?
      refs.scan(/#(\d+)/).each { |m| self.issue_numbers << m[0].to_i }
    end
  end

  def new?
    @raw_data['created_at'] == @raw_data['updated_at']
  end

end
