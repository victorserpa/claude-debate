class User < ApplicationRecord
  enum :role, { member: 0, admin: 1 }
end
