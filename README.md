# gdpr

The new EU General Data Protection Regulation (aka GDPR) made every company including BlindSideNetworks, go further to protect your data. We want to make you aware of some recent related updates:

We added two scripts bbb-user-data && bbb-user-data-forget.
These two scripts will be able to help you grab all the information that you have on a user and forget that information accordingly.

## bbb-user-data

#### Format
./bbb-user-data -u \<username> -r \<RecordingPath>

Takes a username (aka user_id) and a RecordingPath.
Return all the user information found in a specific recording in info.csv file. 

#### Example:
./bbb-user-data -u w_rrcbnpzrnqre -r ~/GDPR/fd4fd4ce206810310fc8b2825a6ca2ef2e7c7ce0-1525773083919

## bbb-user-data-forget

#### Format
./bbb-user-data-forget -u \<username> -r \<RecordingPath>

Takes a username (aka user_id) and a RecordingPath.
Delete all the information regarding the specific user. Including all the camera recording, presentation and Deskshare

#### Example:
./bbb-user-data-forget -u w_rrcbnpzrnqre -r ~/GDPR/fd4fd4ce206810310fc8b2825a6ca2ef2e7c7ce0-1525773083919

