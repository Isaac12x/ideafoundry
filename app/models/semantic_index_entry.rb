# Manifest of KB docs already sent to the semantic sidecar: `sig` (name + file/note stat + cached OCR) says whether a file changed
# since, so the KB delta only reads files whose sig moved.
class SemanticIndexEntry < ApplicationRecord
  belongs_to :user
end
