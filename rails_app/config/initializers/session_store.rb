# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_jcp_session',
  :secret      => 'ac8588cf22b9f36a11a1f58445d3ce3ac34405fb444fd8bd1b8f1b098c4a245fb2894d7c9e24854f5cdb4365ecb66aac10ecedba652c3b09c9ca35840c98fb13'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
