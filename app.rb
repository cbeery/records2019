require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/partial'
require 'google/apis/sheets_v4'
require 'signet/oauth_2/client'
require 'dotenv/load'
require 'sass'

# Sinatra partial config
set :partial_template_engine, :erb
enable :partial_underscores

# Sass style sheet
get('/styles.css') do
	# This was a good hint https://groups.google.com/forum/#!msg/sinatrarb/pLOyBFqbCi0/LbVDYlfphnAJ
	drive_setup
	@color = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'CSS!A1:A1').values[0][0]
  scss(erb :styles, layout: false)
end

get '/' do
	drive_setup
	cb_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'CB should listen to').values
	hef_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Hef should listen to').values

	# Drop header row, select album cover (column 10) not nil, reverse sort
	@cb_data = cb_rows.drop(1).select{|row| !row[10].nil?}.reverse
	@hef_data = hef_rows.drop(1).select{|row| !row[10].nil?}.reverse

	@cb_latest_week_of_data = @cb_data[0][0] # first row (reversed), first column
	@hef_latest_week_of_data = @hef_data[0][0]
	@latest_week_of_data = [@cb_latest_week_of_data, @hef_latest_week_of_data].min.to_i
	# @current_week = Date.today.cweek # Week starts on Monday
	@current_week = Date.today.cweek + (Date.today.sunday? ? 1 : 0)
	# @current_week = 7	

	# Define this_week_index for first row of data to use (normally This/Current Week)
	# this_week_index is latest week of data - current week, unless that's less than -1
	@this_week_index = [(@latest_week_of_data - @current_week), -1].max
	@last_week_index = @this_week_index + 1

	@third_level_display_count = 5 # Number to show at third level ("Recently...")
	@third_level_indices = ((@last_week_index + 1)..(@last_week_index + @third_level_display_count))
	@fourth_level_indices = ((@last_week_index + @third_level_display_count + 1)..52) # max is 52 weeks

	# Don't show this week if current week later than last week of data
	@show_this_week = @this_week_index >= 0 

	erb :index
end

get '/api/latest' do
	drive_setup
	cb_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'CB should listen to').values
	hef_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Hef should listen to').values

	@cb_data = cb_rows.drop(1).select{|row| !row[10].nil?}
	@hef_data = hef_rows.drop(1).select{|row| !row[10].nil?}

	latest_row = [@cb_data.size, @hef_data.size].min
	latest_index = latest_row - 1

	cb_latest, hef_latest = @cb_data[latest_index], @hef_data[latest_index]

	content_type 'application/json'
	# {size: @cb_data.size, latest_week: @cb_data.last[0]}.to_json
	{week: latest_row, hef: {artist: hef_latest[3], record: hef_latest[4], year: hef_latest[5], cover_img_url: hef_latest[10]}, cb: {artist: cb_latest[3], record: cb_latest[4], year: cb_latest[5], cover_img_url: cb_latest[10]}}.to_json

end

helpers do

	def spotify_link_album_cover(record_data_row)
		img = %Q{<img src="#{record_data_row[10]}" class="img img-responsive img-thumbnail"/>}
		# Spotify link around the cover, or just the cover if no Spotify link
		record_data_row[9].empty? ? img : %Q{<a href="#{record_data_row[9]}" title="#{record_data_row[4]}">#{img}</a>}
	end

	def spotify_link(record_data_row)
		%Q{<a href="#{record_data_row[9]}" title="#{record_data_row[4]}">#{record_data_row[4]}</a>}
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
