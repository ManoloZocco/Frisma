# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.StatusView do
  use Pleroma.Web, :view

  require Pleroma.Constants

  alias Pleroma.Activity
  alias Pleroma.HTML
  alias Pleroma.Maps
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.UserRelationship
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.CommonAPI.Utils
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.PollView
  alias Pleroma.Web.MastodonAPI.StatusView
  alias Pleroma.Web.MediaProxy
  alias Pleroma.Web.PleromaAPI.EmojiReactionController
  alias Pleroma.Web.RichMedia.Parser.Card
  alias Pleroma.Web.RichMedia.Parser.Embed

  import Pleroma.Web.ActivityPub.Visibility, only: [get_visibility: 1, visible_for_user?: 2]

  # This is a naive way to do this, just spawning a process per activity
  # to fetch the preview. However it should be fine considering
  # pagination is restricted to 40 activities at a time
  defp fetch_rich_media_for_activities(activities) do
    Enum.each(activities, fn activity ->
      spawn(fn ->
        Pleroma.Web.RichMedia.Helpers.fetch_data_for_activity(activity)
      end)
    end)
  end

  # TODO: Add cached version.
  defp get_replied_to_activities([]), do: %{}

  defp get_replied_to_activities(activities) do
    activities
    |> Enum.map(fn
      %{data: %{"type" => "Create"}} = activity ->
        object = Object.normalize(activity, fetch: false)
        object && object.data["inReplyTo"] != "" && object.data["inReplyTo"]

      _ ->
        nil
    end)
    |> Enum.filter(& &1)
    |> Activity.create_by_object_ap_id_with_object()
    |> Repo.all()
    |> Enum.reduce(%{}, fn activity, acc ->
      object = Object.normalize(activity, fetch: false)
      if object, do: Map.put(acc, object.data["id"], activity), else: acc
    end)
  end

  defp get_quoted_activities([]), do: %{}

  defp get_quoted_activities(activities) do
    activities
    |> Enum.map(fn
      %{data: %{"type" => "Create"}} = activity ->
        object = Object.normalize(activity, fetch: false)
        object && object.data["quoteUrl"] != "" && object.data["quoteUrl"]

      _ ->
        nil
    end)
    |> Enum.filter(& &1)
    |> Activity.create_by_object_ap_id_with_object()
    |> Repo.all()
    |> Enum.reduce(%{}, fn activity, acc ->
      object = Object.normalize(activity, fetch: false)
      if object, do: Map.put(acc, object.data["id"], activity), else: acc
    end)
  end

  # Check if the user reblogged this status
  defp reblogged?(activity, %User{ap_id: ap_id}) do
    with %Object{data: %{"announcements" => announcements}} when is_list(announcements) <-
           Object.normalize(activity, fetch: false) do
      ap_id in announcements
    else
      _ -> false
    end
  end

  # False if the user is logged out
  defp reblogged?(_activity, _user), do: false

  def render("index.json", opts) do
    reading_user = opts[:for]

    # To do: check AdminAPIControllerTest on the reasons behind nil activities in the list
    activities = Enum.filter(opts.activities, & &1)

    # Start fetching rich media before doing anything else, so that later calls to get the cards
    # only block for timeout in the worst case, as opposed to
    # length(activities_with_links) * timeout
    fetch_rich_media_for_activities(activities)
    replied_to_activities = get_replied_to_activities(activities)
    quoted_activities = get_quoted_activities(activities)

    parent_activities =
      activities
      |> Enum.filter(&(&1.data["type"] == "Announce" && &1.data["object"]))
      |> Enum.map(&Object.normalize(&1, fetch: false).data["id"])
      |> Activity.create_by_object_ap_id()
      |> Activity.with_preloaded_object(:left)
      |> Activity.with_preloaded_bookmark(reading_user)
      |> Activity.with_set_thread_muted_field(reading_user)
      |> Repo.all()

    relationships_opt =
      cond do
        Map.has_key?(opts, :relationships) ->
          opts[:relationships]

        is_nil(reading_user) ->
          UserRelationship.view_relationships_option(nil, [])

        true ->
          # Note: unresolved users are filtered out
          actors =
            (activities ++ parent_activities)
            |> Enum.map(&CommonAPI.get_user(&1.data["actor"], false))
            |> Enum.filter(& &1)

          UserRelationship.view_relationships_option(reading_user, actors, subset: :source_mutes)
      end

    opts =
      opts
      |> Map.put(:replied_to_activities, replied_to_activities)
      |> Map.put(:quoted_activities, quoted_activities)
      |> Map.put(:parent_activities, parent_activities)
      |> Map.put(:relationships, relationships_opt)

    safe_render_many(activities, StatusView, "show.json", opts)
  end

  def render(
        "show.json",
        %{activity: %{data: %{"type" => "Announce", "object" => _object}} = activity} = opts
      ) do
    user = CommonAPI.get_user(activity.data["actor"])
    created_at = Utils.to_masto_date(activity.data["published"])
    object = Object.normalize(activity, fetch: false)

    reblogged_parent_activity =
      if opts[:parent_activities] do
        Activity.Queries.find_by_object_ap_id(
          opts[:parent_activities],
          object.data["id"]
        )
      else
        Activity.create_by_object_ap_id(object.data["id"])
        |> Activity.with_preloaded_bookmark(opts[:for])
        |> Activity.with_set_thread_muted_field(opts[:for])
        |> Repo.one()
      end

    reblog_rendering_opts = Map.put(opts, :activity, reblogged_parent_activity)
    reblogged = render("show.json", reblog_rendering_opts)

    favorited = opts[:for] && opts[:for].ap_id in (object.data["likes"] || [])

    bookmarked = Activity.get_bookmark(reblogged_parent_activity, opts[:for]) != nil

    mentions =
      activity.recipients
      |> Enum.map(fn ap_id -> User.get_cached_by_ap_id(ap_id) end)
      |> Enum.filter(& &1)
      |> Enum.map(fn user -> AccountView.render("mention.json", %{user: user}) end)

    {pinned?, pinned_at} = pin_data(object, user)

    %{
      id: to_string(activity.id),
      uri: object.data["id"],
      url: object.data["id"],
      account:
        AccountView.render("show.json", %{
          user: user,
          for: opts[:for]
        }),
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      reblog: reblogged,
      content: reblogged[:content] || "",
      created_at: created_at,
      reblogs_count: 0,
      replies_count: 0,
      favourites_count: 0,
      reblogged: reblogged?(reblogged_parent_activity, opts[:for]),
      favourited: present?(favorited),
      bookmarked: present?(bookmarked),
      muted: false,
      pinned: pinned?,
      sensitive: false,
      spoiler_text: "",
      visibility: get_visibility(activity),
      media_attachments: reblogged[:media_attachments] || [],
      mentions: mentions,
      tags: reblogged[:tags] || [],
      application: build_application(object.data["generator"]),
      language: object.data["language"],
      emojis: [],
      pleroma: %{
        local: activity.local,
        pinned_at: pinned_at
      }
    }
  end

  def render("show.json", %{activity: %{data: %{"object" => _object}} = activity} = opts) do
    object = Object.normalize(activity, fetch: false)

    user = CommonAPI.get_user(activity.data["actor"])
    user_follower_address = user.follower_address

    like_count = object.data["like_count"] || 0
    announcement_count = object.data["announcement_count"] || 0

    hashtags = Object.hashtags(object)
    sensitive = object.data["sensitive"] || Enum.member?(hashtags, "nsfw")

    tags = Object.tags(object)

    tag_mentions =
      tags
      |> Enum.filter(fn tag -> is_map(tag) and tag["type"] == "Mention" end)
      |> Enum.map(fn tag -> tag["href"] end)

    mentions =
      (object.data["to"] ++ tag_mentions)
      |> Enum.uniq()
      |> Enum.map(fn
        Pleroma.Constants.as_public() -> nil
        ^user_follower_address -> nil
        ap_id -> User.get_cached_by_ap_id(ap_id)
      end)
      |> Enum.filter(& &1)
      |> Enum.map(fn user -> AccountView.render("mention.json", %{user: user}) end)

    favorited = opts[:for] && opts[:for].ap_id in (object.data["likes"] || [])

    bookmarked = Activity.get_bookmark(activity, opts[:for]) != nil

    client_posted_this_activity = opts[:for] && user.id == opts[:for].id

    expires_at =
      with true <- client_posted_this_activity,
           %Oban.Job{scheduled_at: scheduled_at} <-
             Pleroma.Workers.PurgeExpiredActivity.get_expiration(activity.id) do
        scheduled_at
      else
        _ -> nil
      end

    thread_muted? =
      cond do
        is_nil(opts[:for]) -> false
        is_boolean(activity.thread_muted?) -> activity.thread_muted?
        true -> CommonAPI.thread_muted?(opts[:for], activity)
      end

    attachment_data = object.data["attachment"] || []
    attachments = render_many(attachment_data, StatusView, "attachment.json", as: :attachment)

    created_at = Utils.to_masto_date(object.data["published"])

    edited_at =
      with %{"updated" => updated} <- object.data,
           date <- Utils.to_masto_date(updated),
           true <- date != "" do
        date
      else
        _ ->
          nil
      end

    reply_to = get_reply_to(activity, opts)
    reply_to_user = reply_to && CommonAPI.get_user(reply_to.data["actor"])

    quote_activity = get_quote(activity, opts)

    quote_id =
      case quote_activity do
        %Activity{id: id} -> id
        _ -> nil
      end

    quote_post =
      if visible_for_user?(quote_activity, opts[:for]) and opts[:show_quote] != false do
        quote_rendering_opts = Map.merge(opts, %{activity: quote_activity, show_quote: false})
        render("show.json", quote_rendering_opts)
      else
        nil
      end

    history_len =
      1 +
        (Object.Updater.history_for(object.data)
         |> Map.get("orderedItems")
         |> length())

    # See render("history.json", ...) for more details
    # Here the implicit index of the current content is 0
    chrono_order = history_len - 1

    content =
      object
      |> render_content()

    content_html =
      content
      |> Activity.HTML.get_cached_scrubbed_html_for_activity(
        User.html_filter_policy(opts[:for]),
        activity,
        "mastoapi:content:#{chrono_order}"
      )

    content_plaintext =
      content
      |> Activity.HTML.get_cached_stripped_html_for_activity(
        activity,
        "mastoapi:content:#{chrono_order}"
      )

    summary = object.data["summary"] || ""

    card =
      render("card.json", %{
        embed: Pleroma.Web.RichMedia.Helpers.fetch_data_for_activity(activity)
      })

    url =
      if user.local do
        Pleroma.Web.Router.Helpers.o_status_url(Pleroma.Web.Endpoint, :notice, activity)
      else
        object.data["url"] || object.data["external_url"] || object.data["id"]
      end

    direct_conversation_id =
      with {_, nil} <- {:direct_conversation_id, opts[:direct_conversation_id]},
           {_, true} <- {:include_id, opts[:with_direct_conversation_id]},
           {_, %User{} = for_user} <- {:for_user, opts[:for]} do
        Activity.direct_conversation_id(activity, for_user)
      else
        {:direct_conversation_id, participation_id} when is_integer(participation_id) ->
          participation_id

        _e ->
          nil
      end

    emoji_reactions =
      object
      |> Object.get_emoji_reactions()
      |> EmojiReactionController.filter_allowed_users(
        opts[:for],
        Map.get(opts, :with_muted, false)
      )
      |> Stream.map(fn {emoji, users, url} ->
        build_emoji_map(emoji, users, url, opts[:for])
      end)
      |> Enum.to_list()

    # Status muted state (would do 1 request per status unless user mutes are preloaded)
    muted =
      thread_muted? ||
        UserRelationship.exists?(
          get_in(opts, [:relationships, :user_relationships]),
          :mute,
          opts[:for],
          user,
          fn for_user, user -> User.mutes?(for_user, user) end
        )

    {pinned?, pinned_at} = pin_data(object, user)

    %{
      id: to_string(activity.id),
      uri: object.data["id"],
      url: url,
      account:
        AccountView.render("show.json", %{
          user: user,
          for: opts[:for]
        }),
      in_reply_to_id: reply_to && to_string(reply_to.id),
      in_reply_to_account_id: reply_to_user && to_string(reply_to_user.id),
      reblog: nil,
      card: card,
      content: content_html,
      text: opts[:with_source] && get_source_text(object.data["source"]),
      created_at: created_at,
      edited_at: edited_at,
      reblogs_count: announcement_count,
      replies_count: object.data["repliesCount"] || 0,
      favourites_count: like_count,
      reblogged: reblogged?(activity, opts[:for]),
      favourited: present?(favorited),
      bookmarked: present?(bookmarked),
      muted: muted,
      pinned: pinned?,
      sensitive: sensitive,
      spoiler_text: summary,
      visibility: get_visibility(object),
      media_attachments: attachments,
      poll: render(PollView, "show.json", object: object, for: opts[:for]),
      mentions: mentions,
      tags: build_tags(tags),
      application: build_application(object.data["generator"]),
      language: object.data["language"],
      emojis: build_emojis(object.data["emoji"]),
      pleroma: %{
        local: activity.local,
        context: object.data["context"],
        in_reply_to_account_acct: reply_to_user && reply_to_user.nickname,
        quote: quote_post,
        quote_id: quote_id,
        quote_url: object.data["quoteUrl"],
        quote_visible: visible_for_user?(quote_activity, opts[:for]),
        content: %{"text/plain" => content_plaintext},
        spoiler_text: %{"text/plain" => summary},
        expires_at: expires_at,
        direct_conversation_id: direct_conversation_id,
        thread_muted: thread_muted?,
        emoji_reactions: emoji_reactions,
        parent_visible: visible_for_user?(reply_to, opts[:for]),
        pinned_at: pinned_at,
        content_type: opts[:with_source] && (object.data["content_type"] || "text/plain"),
        quotes_count: object.data["quotesCount"] || 0,
        event: build_event(object.data, opts[:for])
      }
    }
  end

  def render("show.json", _) do
    nil
  end

  def render("card.json", %{embed: %Embed{} = embed}) do
    with {:ok, %Card{} = card} <- Card.parse(embed) do
      Card.to_map(card)
    else
      _ -> nil
    end
  end

  def render("history.json", %{activity: %{data: %{"object" => _object}} = activity} = opts) do
    object = Object.normalize(activity, fetch: false)

    hashtags = Object.hashtags(object)

    user = CommonAPI.get_user(activity.data["actor"])

    past_history =
      Object.Updater.history_for(object.data)
      |> Map.get("orderedItems")
      |> Enum.map(&Map.put(&1, "id", object.data["id"]))
      |> Enum.map(&%Object{data: &1, id: object.id})

    history =
      [object | past_history]
      # Mastodon expects the original to be at the first
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {object, chrono_order} ->
        %{
          # The history is prepended every time there is a new edit.
          # In chrono_order, the oldest item is always at 0, and so on.
          # The chrono_order is an invariant kept between edits.
          chrono_order: chrono_order,
          object: object
        }
      end)

    individual_opts =
      opts
      |> Map.put(:as, :item)
      |> Map.put(:user, user)
      |> Map.put(:hashtags, hashtags)

    render_many(history, StatusView, "history_item.json", individual_opts)
  end

  def render(
        "history_item.json",
        %{
          activity: activity,
          user: user,
          item: %{object: object, chrono_order: chrono_order},
          hashtags: hashtags
        } = opts
      ) do
    sensitive = object.data["sensitive"] || Enum.member?(hashtags, "nsfw")

    attachment_data = object.data["attachment"] || []
    attachments = render_many(attachment_data, StatusView, "attachment.json", as: :attachment)

    created_at = Utils.to_masto_date(object.data["updated"] || object.data["published"])

    content =
      object
      |> render_content()

    content_html =
      content
      |> Activity.HTML.get_cached_scrubbed_html_for_activity(
        User.html_filter_policy(opts[:for]),
        activity,
        "mastoapi:content:#{chrono_order}"
      )

    summary = object.data["summary"] || ""

    %{
      account:
        AccountView.render("show.json", %{
          user: user,
          for: opts[:for]
        }),
      content: content_html,
      sensitive: sensitive,
      spoiler_text: summary,
      created_at: created_at,
      media_attachments: attachments,
      emojis: build_emojis(object.data["emoji"]),
      poll: render(PollView, "show.json", object: object, for: opts[:for])
    }
  end

  def render("source.json", %{activity: %{data: %{"object" => _object}} = activity} = _opts) do
    object = Object.normalize(activity, fetch: false)

    %{
      id: activity.id,
      text: get_source_text(Map.get(object.data, "source", "")),
      spoiler_text: Map.get(object.data, "summary", ""),
      content_type: get_source_content_type(object.data["source"]),
      location: build_source_location(object.data)
    }
  end

  def render("card.json", %{rich_media: rich_media, page_url: page_url}) do
    page_url_data = URI.parse(page_url)

    page_url_data =
      if is_binary(rich_media["url"]) do
        URI.merge(page_url_data, URI.parse(rich_media["url"]))
      else
        page_url_data
      end

    page_url = page_url_data |> to_string

    image_url_data =
      if is_binary(rich_media["image"]) do
        URI.parse(rich_media["image"])
      else
        nil
      end

    image_url = build_image_url(image_url_data, page_url_data)

    %{
      type: "link",
      provider_name: page_url_data.host,
      provider_url: page_url_data.scheme <> "://" <> page_url_data.host,
      url: page_url,
      image: image_url |> MediaProxy.url(),
      title: rich_media["title"] || "",
      description: rich_media["description"] || "",
      pleroma: %{
        opengraph: rich_media
      }
    }
  end

  def render("card.json", %{embed: %Card{} = card}), do: Card.to_map(card)
  def render("card.json", _), do: nil

  def render("attachment.json", %{attachment: attachment}) do
    [attachment_url | _] = attachment["url"]
    media_type = attachment_url["mediaType"] || attachment_url["mimeType"] || "image"
    href_remote = attachment_url["href"]
    href = href_remote |> MediaProxy.url()
    href_preview = attachment_url["href"] |> MediaProxy.preview_url()
    meta = render("attachment_meta.json", %{attachment: attachment})

    type =
      cond do
        String.contains?(media_type, "image") -> "image"
        String.contains?(media_type, "video") -> "video"
        String.contains?(media_type, "audio") -> "audio"
        true -> "unknown"
      end

    attachment_id =
      with {_, ap_id} when is_binary(ap_id) <- {:ap_id, attachment["id"]},
           {_, %Object{data: _object_data, id: object_id}} <-
             {:object, Object.get_by_ap_id(ap_id)} do
        to_string(object_id)
      else
        _ ->
          <<hash_id::signed-32, _rest::binary>> = :crypto.hash(:md5, href)
          to_string(attachment["id"] || hash_id)
      end

    %{
      id: attachment_id,
      url: href,
      remote_url: href_remote,
      preview_url: href_preview,
      text_url: href,
      type: type,
      description: attachment["name"],
      pleroma: %{mime_type: media_type},
      blurhash: attachment["blurhash"]
    }
    |> Maps.put_if_present(:meta, meta)
  end

  def render("attachment_meta.json", %{
        attachment: %{"url" => [%{"width" => width, "height" => height} | _]}
      })
      when is_integer(width) and is_integer(height) do
    %{
      original: %{
        width: width,
        height: height,
        aspect: width / height
      }
    }
  end

  def render("attachment_meta.json", _), do: nil

  def render("context.json", %{activity: activity, activities: activities, user: user}) do
    %{ancestors: ancestors, descendants: descendants} =
      activities
      |> Enum.reverse()
      |> Enum.group_by(fn %{id: id} -> if id < activity.id, do: :ancestors, else: :descendants end)
      |> Map.put_new(:ancestors, [])
      |> Map.put_new(:descendants, [])

    %{
      ancestors: render("index.json", for: user, activities: ancestors, as: :activity),
      descendants: render("index.json", for: user, activities: descendants, as: :activity)
    }
  end

  def render("translation.json", %{
        content: content,
        detected_source_language: detected_source_language,
        provider: provider
      }) do
    %{content: content, detected_source_language: detected_source_language, provider: provider}
  end

  def get_reply_to(activity, %{replied_to_activities: replied_to_activities}) do
    object = Object.normalize(activity, fetch: false)

    with nil <- replied_to_activities[object.data["inReplyTo"]] do
      # If user didn't participate in the thread
      Activity.get_in_reply_to_activity(activity)
    end
  end

  def get_reply_to(%{data: %{"object" => _object}} = activity, _) do
    object = Object.normalize(activity, fetch: false)

    if object.data["inReplyTo"] && object.data["inReplyTo"] != "" do
      Activity.get_create_by_object_ap_id(object.data["inReplyTo"])
    else
      nil
    end
  end

  def get_quote(activity, %{quoted_activities: quoted_activities}) do
    object = Object.normalize(activity, fetch: false)

    with nil <- quoted_activities[object.data["quoteUrl"]] do
      # For when a quote post is inside an Announce
      Activity.get_create_by_object_ap_id_with_object(object.data["quoteUrl"])
    end
  end

  def get_quote(%{data: %{"object" => _object}} = activity, _) do
    object = Object.normalize(activity, fetch: false)

    if object.data["quoteUrl"] && object.data["quoteUrl"] != "" do
      Activity.get_create_by_object_ap_id(object.data["quoteUrl"])
    else
      nil
    end
  end

  def render_content(%{data: %{"name" => name, "type" => type}} = object)
      when not is_nil(name) and name != "" and type != "Event" do
    url = object.data["url"] || object.data["id"]

    "<p><a href=\"#{url}\">#{name}</a></p>#{object.data["content"]}"
  end

  def render_content(object), do: object.data["content"] || ""

  @doc """
  Builds a dictionary tags.

  ## Examples

  iex> Pleroma.Web.MastodonAPI.StatusView.build_tags(["fediverse", "nextcloud"])
  [{"name": "fediverse", "url": "/tag/fediverse"},
   {"name": "nextcloud", "url": "/tag/nextcloud"}]

  """
  @spec build_tags(list(any())) :: list(map())
  def build_tags(object_tags) when is_list(object_tags) do
    object_tags
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&%{name: &1, url: "#{Pleroma.Web.Endpoint.url()}/tag/#{URI.encode(&1)}"})
  end

  def build_tags(_), do: []

  @doc """
  Builds list emojis.

  Arguments: `nil` or list tuple of name and url.

  Returns list emojis.

  ## Examples

  iex> Pleroma.Web.MastodonAPI.StatusView.build_emojis([{"2hu", "corndog.png"}])
  [%{shortcode: "2hu", static_url: "corndog.png", url: "corndog.png", visible_in_picker: false}]

  """
  @spec build_emojis(nil | list(tuple())) :: list(map())
  def build_emojis(nil), do: []

  def build_emojis(emojis) do
    emojis
    |> Enum.map(fn {name, url} ->
      name = HTML.strip_tags(name)

      url =
        url
        |> HTML.strip_tags()
        |> MediaProxy.url()

      %{shortcode: name, url: url, static_url: url, visible_in_picker: false}
    end)
  end

  defp build_event(%{"type" => "Event"} = data, for_user) do
    %{
      name: data["name"],
      start_time: data["startTime"],
      end_time: data["endTime"],
      join_mode: data["joinMode"],
      participants_count: data["participation_count"],
      location: build_event_location(data["location"]),
      join_state: build_event_join_state(for_user, data["id"]),
      participation_request_count: maybe_put_participation_request_count(data, for_user)
    }
  end

  defp build_event(_, _), do: nil

  defp build_event_location(%{"type" => "Place"} = location) do
    %{
      name: location["name"],
      url: location["url"],
      longitude: location["longitude"],
      latitude: location["latitude"]
    }
    |> maybe_put_address(location["address"])
  end

  defp build_event_location(_), do: nil

  defp maybe_put_address(location, %{"type" => "PostalAddress"} = address) do
    Map.merge(location, %{
      street: address["streetAddress"],
      postal_code: address["postalCode"],
      locality: address["addressLocality"],
      region: address["addressRegion"],
      country: address["addressCountry"]
    })
  end

  defp maybe_put_address(location, _), do: location

  defp build_event_join_state(%{ap_id: actor}, id) do
    latest_join = Pleroma.Web.ActivityPub.Utils.get_existing_join(actor, id)

    if latest_join do
      latest_join.data["state"]
    end
  end

  defp build_event_join_state(_, _), do: nil

  defp maybe_put_participation_request_count(%{"actor" => actor} = data, %{ap_id: actor}) do
    data["participation_request_count"]
  end

  defp maybe_put_participation_request_count(_, _), do: nil

  defp present?(nil), do: false
  defp present?(false), do: false
  defp present?(_), do: true

  defp pin_data(%Object{data: %{"id" => object_id}}, %User{pinned_objects: pinned_objects}) do
    if pinned_at = pinned_objects[object_id] do
      {true, Utils.to_masto_date(pinned_at)}
    else
      {false, nil}
    end
  end

  defp build_emoji_map(emoji, users, url, current_user) do
    %{
      name: Pleroma.Web.PleromaAPI.EmojiReactionView.emoji_name(emoji, url),
      count: length(users),
      url: MediaProxy.url(url),
      me: !!(current_user && current_user.ap_id in users),
      account_ids: Enum.map(users, fn user -> User.get_cached_by_ap_id(user).id end)
    }
  end

  @spec build_application(map() | nil) :: map() | nil
  defp build_application(%{"type" => _type, "name" => name, "url" => url}),
    do: %{name: name, website: url}

  defp build_application(_), do: nil

  # Workaround for Elixir issue #10771
  # Avoid applying URI.merge unless necessary
  # TODO: revert to always attempting URI.merge(image_url_data, page_url_data)
  # when Elixir 1.12 is the minimum supported version
  @spec build_image_url(struct() | nil, struct()) :: String.t() | nil
  defp build_image_url(
         %URI{scheme: image_scheme, host: image_host} = image_url_data,
         %URI{} = _page_url_data
       )
       when not is_nil(image_scheme) and not is_nil(image_host) do
    image_url_data |> to_string
  end

  defp build_image_url(%URI{} = image_url_data, %URI{} = page_url_data) do
    URI.merge(page_url_data, image_url_data) |> to_string
  end

  defp build_image_url(_, _), do: nil

  defp get_source_text(%{"content" => content} = _source) do
    content
  end

  defp get_source_text(source) when is_binary(source) do
    source
  end

  defp get_source_text(_) do
    ""
  end

  defp get_source_content_type(%{"mediaType" => type} = _source) do
    type
  end

  defp get_source_content_type(_source) do
    Utils.get_content_type(nil)
  end

  def build_source_location(%{"location_id" => location_id}) when is_binary(location_id) do
    location = Geospatial.Service.service().get_by_id(location_id) |> List.first()

    if location do
      Pleroma.Web.PleromaAPI.SearchView.render("show_location.json", %{location: location})
    else
      nil
    end
  end

  def build_source_location(_), do: nil
end
