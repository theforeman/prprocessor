class PullRequest

  attr_accessor :raw_data, :title

  def initialize(raw_data)
    self.raw_data = raw_data
    self.title = raw_data['title']
  end

  def issue_number
    number = @title.match(/(((F|f)ixes)|((R|r)efs)) #\d+/)
    return false if number.nil?
    number[0].split('#')[1]
  end

  def new?
    @raw_data['created_at'] == @raw_data['updated_at']
  end

end
