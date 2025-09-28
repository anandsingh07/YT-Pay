const express = require("express");
const axios = require("axios");
const router = express.Router();

const API_KEY = process.env.YOUTUBE_API_KEY;

router.get("/", async (req, res) => {
  const { query } = req.query;

  if (!query) return res.status(400).json({ error: "Query is required" });

  try {
    console.log("Searching for:", query);

    const searchUrl = `https://www.googleapis.com/youtube/v3/search?part=snippet&type=channel&q=${encodeURIComponent(
      query
    )}&key=${API_KEY}`;

    const searchResponse = await axios.get(searchUrl);

    if (!searchResponse.data.items || searchResponse.data.items.length === 0) {
      return res.status(404).json({ error: "No channel found" });
    }

    const channel = searchResponse.data.items[0];
    if (!channel.id?.channelId) {
      return res.status(404).json({ error: "Channel ID not found" });
    }

    const channelId = channel.id.channelId;
    const channelUrl = `https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&id=${channelId}&key=${API_KEY}`;

    const channelResponse = await axios.get(channelUrl);
    const info = channelResponse.data.items[0];

    res.json({
      id: info.id,
      name: info.snippet.title,
      logo: info.snippet.thumbnails.default.url,
      subscribers: info.statistics.subscriberCount || 0,
    });
  } catch (err) {
    console.error("YouTube API Error:", err.response?.data || err.message);
    res
      .status(err.response?.status || 500)
      .json({ error: err.response?.data?.error?.message || "Failed to fetch channel info" });
  }
});

module.exports = router;
