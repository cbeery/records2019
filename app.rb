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

get('/report.css') do
  scss(erb :report, layout: false)
end

# web

get '/' do
	if Date.today.year > 2019
		get_data_for_summary_layout
		erb :summary
	else
		get_data_for_original_layout
		erb :index
	end
end

get '/original' do
	get_data_for_original_layout
	erb :index
end

get '/summary' do
	get_data_for_summary_layout
	erb :summary
end

get '/numbers' do
	get_data_for_summary_layout
	@subhead = 'Numbers.'

	@hef_ratings = @hef_data.map{|h| h[11].to_f}.select{|h| !h.zero?}
	@hef_avg = (@hef_ratings.sum / @hef_ratings.count).round(1)
	@hef_max = @hef_ratings.max
	@hef_min = @hef_ratings.min
	@hef_max_records = @hef_data.select{|h| h[7].to_f == @hef_max}.map{|h| artist_album(h)}.join(', ')
	@hef_min_records = @hef_data.select{|h| h[7].to_f == @hef_min}.map{|h| artist_album(h)}.join(', ')

	@cb_ratings = @cb_data.map{|c| c[7].to_f}.select{|c| !c.zero?}
	@cb_avg = (@cb_ratings.sum / @cb_ratings.count).round(1)
	@cb_max = @cb_ratings.max
	@cb_min = @cb_ratings.min
	@cb_max_records = @cb_data.select{|c| c[7].to_f == @cb_max}.map{|c| artist_album(c)}.join(', ')
	@cb_min_records = @cb_data.select{|c| c[7].to_f == @cb_min}.map{|c| artist_album(c)}.join(', ')

	@cb_to_hef_ratings = @hef_data.map{|c| c[8].to_f}.select{|c| !c.zero?}
	@cb_to_hef_avg = (@cb_to_hef_ratings.sum / @cb_to_hef_ratings.count).round(1)
	@cb_to_hef_max = @cb_to_hef_ratings.max
	@cb_to_hef_min = @cb_to_hef_ratings.min
	@cb_to_hef_max_records = @hef_data.select{|c| c[8].to_f == @cb_to_hef_max}.map{|c| artist_album(c)}.join(', ')
	@cb_to_hef_min_records = @hef_data.select{|c| c[8].to_f == @cb_to_hef_min}.map{|c| artist_album(c)}.join(', ')

	@combined_data = []
	@hef_data.each_with_index{|h,i| @combined_data << h + @cb_data[i]}
	@combined_rated_data = @combined_data.select{|c| !c[7].empty?}
	@combined_rated_data.sort_by!{|c| c[11].to_f+c[19].to_f}
	@worst_week_total = @combined_rated_data.first[11].to_f + @combined_rated_data.first[19].to_f
	@best_week_total = @combined_rated_data.last[11].to_f + @combined_rated_data.last[19].to_f
	@worst_weeks = @combined_rated_data.select{|c| c[11].to_f + c[19].to_f == @worst_week_total}
	@best_weeks = @combined_rated_data.select{|c| c[11].to_f + c[19].to_f == @best_week_total}

	
	erb :numbers
end

# api

get '/api/latest' do
	drive_setup
	grab_the_data
	
	latest_row = [@cb_completed_rows.size, @hef_completed_rows.size].min
	latest_index = latest_row - 1

	cb_latest, hef_latest = @cb_completed_rows[latest_index], @hef_completed_rows[latest_index]

	content_type 'application/json'
	{week: latest_row, hef: {artist: hef_latest[3], record: hef_latest[4], year: hef_latest[5], cover_img_url: hef_latest[10], spotify_url: hef_latest[9]}, cb: {artist: cb_latest[3], record: cb_latest[4], year: cb_latest[5], cover_img_url: cb_latest[10], spotify_url: cb_latest[9]}}.to_json

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

	def artist_album(record_data_row)
		%Q{#{record_data_row[3]} <a href="#{record_data_row[9]}"><em>#{record_data_row[4]}</em></a>}
	end

end

private

def get_data_for_original_layout
	drive_setup
	grab_the_data

	@cb_data = @cb_completed_rows.reverse
	@hef_data = @hef_completed_rows.reverse

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
end

def get_data_for_summary_layout
	@styles = 'report'
	@title ='Records. 2019.'
	@subhead = 'Year-end summary report.'
	@commentary = (params[:commentary] == 'on')

	drive_setup
	grab_the_data

	@cb_data = @cb_completed_rows
	@hef_data = @hef_completed_rows
end



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

def get_all_the_rows
	@cb_all_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'CB should listen to').values
	@hef_all_rows = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Hef should listen to').values
end

def get_all_the_completed_rows
	# Drop header row, select album cover (column 10) not nil
	@cb_completed_rows = @cb_all_rows.drop(1).select{|row| !row[10].nil?}
	@hef_completed_rows = @hef_all_rows.drop(1).select{|row| !row[10].nil?}
end

def grab_the_data
	get_all_the_rows
	get_all_the_completed_rows
end
