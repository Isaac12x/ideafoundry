# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a default user
user = User.find_or_create_by!(email: 'user@example.com') do |u|
  u.name = 'Default User'
end

# Create some lists
backlog = user.lists.find_or_create_by!(name: 'Backlog') do |l|
  l.position = user.lists.maximum(:position).to_i + 1
end
in_progress = user.lists.find_or_create_by!(name: 'In Progress') do |l|
  l.position = user.lists.maximum(:position).to_i + 1
end
done = user.lists.find_or_create_by!(name: 'Done') do |l|
  l.position = user.lists.maximum(:position).to_i + 1
end

# Create some sample ideas
ideas_data = [
  { title: 'AI-powered recipe generator', state: 'idea_new', trl: 2, difficulty: 6, opportunity: 8, timing: 7 },
  { title: 'Smart home energy optimizer', state: 'triage', trl: 3, difficulty: 7, opportunity: 9, timing: 6 },
  { title: 'Virtual reality fitness app', state: 'first_try', trl: 4, difficulty: 8, opportunity: 7, timing: 8 },
  { title: 'Blockchain voting system', state: 'incubating', trl: 5, difficulty: 9, opportunity: 6, timing: 5 },
  { title: 'Automated plant watering system', state: 'validated', trl: 7, difficulty: 4, opportunity: 5, timing: 6 }
]

ideas_data.each_with_index do |idea_data, index|
  idea = user.ideas.find_or_create_by!(title: idea_data[:title]) do |i|
    i.state = idea_data[:state]
    i.trl = idea_data[:trl]
    i.difficulty = idea_data[:difficulty]
    i.opportunity = idea_data[:opportunity]
    i.timing = idea_data[:timing]
    i.description = "This is a sample description for #{idea_data[:title]}. It contains some details about the idea and its potential implementation."
  end

  # Assign ideas to lists based on their state
  list = case idea.state
         when 'idea_new', 'triage'
           backlog
         when 'first_try', 'second_try', 'incubating'
           in_progress
         when 'validated', 'shipped'
           done
         else
           backlog
         end

  # Create the idea-list association if it doesn't exist
  unless idea.idea_lists.exists?(list: list)
    idea.idea_lists.create!(list: list, position: idea.idea_lists.count + 1)
  end
end

puts "Created #{User.count} user(s)"
puts "Created #{List.count} list(s)"
puts "Created #{Idea.count} idea(s)"
puts "Created #{IdeaList.count} idea-list association(s)"
