class BackfillInstanceIdsOnFieldDefinitions < ActiveRecord::Migration[8.0]
  def up
    execute("SELECT id, field_definitions FROM templates WHERE field_definitions IS NOT NULL").each do |row|
      id = row['id']
      raw = row['field_definitions']
      next if raw.blank?

      fields = JSON.parse(raw) rescue next
      fields = JSON.parse(fields) if fields.is_a?(String)
      next unless fields.is_a?(Array)

      seen = {}
      fields.each do |fd|
        next unless fd.is_a?(Hash)
        name = fd['name']
        next if name.blank?
        next if fd['instance_id'].present?

        if seen[name]
          fd['instance_id'] = "#{name}_#{SecureRandom.hex(4)}"
        else
          fd['instance_id'] = name
          seen[name] = true
        end
      end

      execute("UPDATE templates SET field_definitions = #{connection.quote(fields.to_json)} WHERE id = #{id}")
    end
  end

  def down
    execute("SELECT id, field_definitions FROM templates WHERE field_definitions IS NOT NULL").each do |row|
      id = row['id']
      raw = row['field_definitions']
      next if raw.blank?

      fields = JSON.parse(raw) rescue next
      next unless fields.is_a?(Array)

      fields.each { |fd| fd.delete('instance_id') if fd.is_a?(Hash) }
      execute("UPDATE templates SET field_definitions = #{connection.quote(fields.to_json)} WHERE id = #{id}")
    end
  end
end
