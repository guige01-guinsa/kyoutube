export const safeErrorCodes = [
  "youtube_config_missing",
  "youtube_input_invalid",
  "youtube_transport_error",
  "youtube_timeout",
  "youtube_quota_exceeded",
  "youtube_response_invalid",
  "youtube_item_invalid",
] as const;

export type YoutubeSearchItem = {
  videoId: string;
  title: string;
  channelTitle: string;
  publishedAt: string;
  thumbnailUrl: string;
  youtubeUrl: string;
  durationSec: number | null;
};
export type YoutubeSuccess = {
  status: "ok";
  data: { items: YoutubeSearchItem[]; nextPageToken: null };
};
export type YoutubeFailure = {
  status: "error";
  errorCode: string;
  httpStatus: number;
};
export const success = (items: YoutubeSearchItem[]): YoutubeSuccess => ({
  status: "ok",
  data: { items, nextPageToken: null },
});
export const failure = (
  errorCode: string,
  httpStatus: number,
): YoutubeFailure => ({ status: "error", errorCode, httpStatus });
