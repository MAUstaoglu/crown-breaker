# Read/repair helpers for a submission that App Store Connect left open.
lane :diag do
  asc_key
  app = Spaceship::ConnectAPI::App.find(APP_ID)
  sub = app.get_in_progress_review_submission(platform: "IOS")
  UI.message("in-progress: #{sub ? "#{sub.id} state=#{sub.state}" : 'none'}")
  app.get_app_store_versions.select { |v| v.version_string == VERSION }.each do |v|
    UI.message("version #{v.version_string} #{v.platform} state=#{v.app_store_state}")
  end
end

# A submission that came back with unresolved issues stays open and blocks the
# next one. Cancel it so a corrected build can be submitted.
lane :cancel_open_submission do
  asc_key
  app = Spaceship::ConnectAPI::App.find(APP_ID)
  sub = app.get_in_progress_review_submission(platform: "IOS")
  UI.user_error!("no in-progress submission") if sub.nil?
  UI.message("cancelling #{sub.id} (state=#{sub.state})")
  sub.cancel_submission
  UI.success("cancel requested")
end
