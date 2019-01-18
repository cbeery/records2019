require 'sinatra'
require 'sinatra/reloader' if development?
require 'google/apis/sheets_v4'
require 'signet/oauth_2/client'
require 'dotenv/load'

GOOGLE_CLIENT_ID = ENV['GOOGLE_CLIENT_ID']
GOOGLE_CLIENT_SECRET = ENV['GOOGLE_CLIENT_SECRET']
REFRESH_TOKEN = ENV['REFRESH_TOKEN']

SHEET_ID = ENV['SHEET_ID']
HEF_RANGE = 'Hef should listen to'
CB_RANGE = 'CB should listen to'

# SHEET_ID = "1LzMYYXxTZec1FkrbCwFjHP-BSGo4fPMHvP4_TlQIq_4"
# HEF_RANGE = "Pockets"

get '/' do
	drive_setup
	@hef = @drive.get_spreadsheet_values(SHEET_ID, HEF_RANGE)
	@cb = @drive.get_spreadsheet_values(SHEET_ID, CB_RANGE)
	erb :index
end

private

def drive_setup
	auth = Signet::OAuth2::Client.new(
	  token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
	  client_id: 						GOOGLE_CLIENT_ID,
	  client_secret: 				GOOGLE_CLIENT_SECRET,
	  refresh_token: 				REFRESH_TOKEN
	)
	auth.fetch_access_token!
	@drive = Google::Apis::SheetsV4::SheetsService.new
	@drive.authorization = auth
end
