require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/partial'
require 'google/apis/sheets_v4'
require 'signet/oauth_2/client'
require 'dotenv/load'

# Sinatra partial config
set :partial_template_engine, :erb
enable :partial_underscores

get '/' do
	drive_setup
	cb_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'CB should listen to').values
	hef_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Hef should listen to').values

	# Drop header row, select album cover (column 10) not nil, reverse sort
	@cb_data = cb_rows.drop(1).select{|row| !row[10].nil?}.reverse
	@hef_data = hef_rows.drop(1).select{|row| !row[10].nil?}.reverse

	cb_latest_week_of_data = @cb_data[0][0] # first row (reversed), first column
	hef_latest_week_of_data = @hef_data[0][0]
	@latest_week_of_data = [cb_latest_week_of_data, hef_latest_week_of_data].min.to_i
	@current_week = Date.today.cweek

	# Define this_week_index for first row of data to use (normally This/Current Week)
	# this_week_index is latest week of data - current week, unless that's less than -1
	@this_week_index = [(@latest_week_of_data - @current_week), -1].max
	@last_week_index = @this_week_index + 1

	@third_level_display_count = 1 # Number to show at third level ("Recently...")
	@third_level_indices = ((@last_week_index + 1)..(@last_week_index + @third_level_display_count))
	@fourth_level_indices = ((@last_week_index + @third_level_display_count + 1)..52) # max in 52 weeks

	# Don't show this week if current week later than last week of data
	@show_this_week = @this_week_index >= 0 

	erb :index
end

helpers do
	def crap
		"shit"
	end
end

private

def drive_setup
	auth = Signet::OAuth2::Client.new(
	  token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
	  client_id: 						ENV['GOOGLE_CLIENT_ID'],
	  client_secret: 				ENV['GOOGLE_CLIENT_SECRET'],
	  refresh_token: 				ENV['REFRESH_TOKEN']
	)
	auth.fetch_access_token!
	@drive = Google::Apis::SheetsV4::SheetsService.new
	@drive.authorization = auth
end
