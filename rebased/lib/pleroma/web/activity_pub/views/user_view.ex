# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.UserView do
  use Pleroma.Web, :view

  alias Pleroma.Keys
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectView
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.Router.Helpers

  import Ecto.Query

  def render("endpoints.json", %{user: %User{nickname: nil, local: true} = _user}) do
    %{"sharedInbox" => Helpers.activity_pub_url(Endpoint, :inbox)}
  end

  def render("endpoints.json", %{user: %User{local: true} = _user}) do
    %{
      "oauthAuthorizationEndpoint" => Helpers.o_auth_url(Endpoint, :authorize),
      "oauthRegistrationEndpoint" => Helpers.app_url(Endpoint, :create),
      "oauthTokenEndpoint" => Helpers.o_auth_url(Endpoint, :token_exchange),
      "sharedInbox" => Helpers.activity_pub_url(Endpoint, :inbox)
    }
  end

  def render("endpoints.json", _), do: %{}

  def render("service.json", %{user: user}) do
    {:ok, _, public_key} = Keys.keys_from_pem(user.keys)
    public_key = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    public_key = :public_key.pem_encode([public_key])

    endpoints = render("endpoints.json", %{user: user})

    %{
      "id" => user.ap_id,
      "type" => "Application",
      "following" => "#{user.ap_id}/following",
      "followers" => "#{user.ap_id}/followers",
      "inbox" => "#{user.ap_id}/inbox",
      "outbox" => "#{user.ap_id}/outbox",
      "name" => "Pleroma",
      "summary" =>
        "An internal service actor for this Pleroma instance.  No user-serviceable parts inside.",
      "url" => user.ap_id,
      "manuallyApprovesFollowers" => false,
      "publicKey" => %{
        "id" => "#{user.ap_id}#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => public_key
      },
      "endpoints" => endpoints,
      "invisible" => User.invisible?(user)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  # the instance itself is not a Person, but instead an Application
  def render("user.json", %{user: %User{nickname: nil} = user}),
    do: render("service.json", %{user: user})

  def render("user.json", %{user: %User{nickname: "internal." <> _} = user}) do
    nickname = user.nickname |> String.split("@") |> List.first()
    render("service.json", %{user: user}) |> Map.put("preferredUsername", nickname)
  end

  def render("user.json", %{user: user}) do
    {:ok, _, public_key} = Keys.keys_from_pem(user.keys)
    public_key = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    public_key = :public_key.pem_encode([public_key])
    user = User.sanitize_html(user)

    endpoints = render("endpoints.json", %{user: user})

    emoji_tags = Transmogrifier.take_emoji_tags(user)

    fields = Enum.map(user.fields, &Map.put(&1, "type", "PropertyValue"))

    capabilities =
      if is_boolean(user.accepts_chat_messages) do
        %{
          "acceptsChatMessages" => user.accepts_chat_messages
        }
      else
        %{}
      end

    birthday =
      if user.show_birthday && user.birthday,
        do: Date.to_iso8601(user.birthday),
        else: nil

    %{
      "id" => user.ap_id,
      "type" => user.actor_type,
      "following" => "#{user.ap_id}/following",
      "followers" => "#{user.ap_id}/followers",
      "inbox" => "#{user.ap_id}/inbox",
      "outbox" => "#{user.ap_id}/outbox",
      "featured" => "#{user.ap_id}/collections/featured",
      "preferredUsername" => user.nickname,
      "name" => user.name,
      "summary" => user.bio,
      "url" => user.ap_id,
      "manuallyApprovesFollowers" => user.is_locked,
      "publicKey" => %{
        "id" => "#{user.ap_id}#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => public_key
      },
      "endpoints" => endpoints,
      "attachment" => fields,
      "tag" => emoji_tags,
      # Note: key name is indeed "discoverable" (not an error)
      "discoverable" => user.is_discoverable,
      "capabilities" => capabilities,
      "alsoKnownAs" => user.also_known_as,
      "vcard:bday" => birthday,
      "vcard:Address" => user.location
    }
    |> Map.merge(maybe_make_image(&User.avatar_url/2, "icon", user))
    |> Map.merge(maybe_make_image(&User.banner_url/2, "image", user))
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("following.json", %{user: user, page: page} = opts) do
    showing_items = (opts[:for] && opts[:for] == user) || !user.hide_follows
    showing_count = showing_items || !user.hide_follows_count

    query = User.get_friends_query(user)
    query = from(user in query, select: [:ap_id])
    following = Repo.all(query)

    total =
      if showing_count do
        length(following)
      else
        0
      end

    collection(following, "#{user.ap_id}/following", page, showing_items, total)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("following.json", %{user: user} = opts) do
    showing_items = (opts[:for] && opts[:for] == user) || !user.hide_follows
    showing_count = showing_items || !user.hide_follows_count

    query = User.get_friends_query(user)
    query = from(user in query, select: [:ap_id])
    following = Repo.all(query)

    total =
      if showing_count do
        length(following)
      else
        0
      end

    %{
      "id" => "#{user.ap_id}/following",
      "type" => "OrderedCollection",
      "totalItems" => total,
      "first" =>
        if showing_items do
          collection(following, "#{user.ap_id}/following", 1, !user.hide_follows)
        else
          "#{user.ap_id}/following?page=1"
        end
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("followers.json", %{user: user, page: page} = opts) do
    showing_items = (opts[:for] && opts[:for] == user) || !user.hide_followers
    showing_count = showing_items || !user.hide_followers_count

    query = User.get_followers_query(user)
    query = from(user in query, select: [:ap_id])
    followers = Repo.all(query)

    total =
      if showing_count do
        length(followers)
      else
        0
      end

    collection(followers, "#{user.ap_id}/followers", page, showing_items, total)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("followers.json", %{user: user} = opts) do
    showing_items = (opts[:for] && opts[:for] == user) || !user.hide_followers
    showing_count = showing_items || !user.hide_followers_count

    query = User.get_followers_query(user)
    query = from(user in query, select: [:ap_id])
    followers = Repo.all(query)

    total =
      if showing_count do
        length(followers)
      else
        0
      end

    %{
      "id" => "#{user.ap_id}/followers",
      "type" => "OrderedCollection",
      "first" =>
        if showing_items do
          collection(followers, "#{user.ap_id}/followers", 1, showing_items, total)
        else
          "#{user.ap_id}/followers?page=1"
        end
    }
    |> maybe_put_total_items(showing_count, total)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("activity_collection.json", %{iri: iri}) do
    %{
      "id" => iri,
      "type" => "OrderedCollection",
      "first" => "#{iri}?page=true"
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("activity_collection_page.json", %{
        activities: activities,
        iri: iri,
        pagination: pagination
      }) do
    collection =
      Enum.map(activities, fn activity ->
        {:ok, data} = Transmogrifier.prepare_outgoing(activity.data)
        data
      end)

    %{
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "orderedItems" => collection
    }
    |> Map.merge(Utils.make_json_ld_header())
    |> Map.merge(pagination)
  end

  def render("featured.json", %{
        user: %{featured_address: featured_address, pinned_objects: pinned_objects}
      }) do
    objects =
      pinned_objects
      |> Enum.sort_by(fn {_, pinned_at} -> pinned_at end, &>=/2)
      |> Enum.map(fn {id, _} ->
        ObjectView.render("object.json", %{object: Object.get_cached_by_ap_id(id)})
      end)

    %{
      "id" => featured_address,
      "type" => "OrderedCollection",
      "orderedItems" => objects,
      "totalItems" => length(objects)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  defp maybe_put_total_items(map, false, _total), do: map

  defp maybe_put_total_items(map, true, total) do
    Map.put(map, "totalItems", total)
  end

  def collection(collection, iri, page, show_items \\ true, total \\ nil) do
    offset = (page - 1) * 10
    items = Enum.slice(collection, offset, 10)
    items = Enum.map(items, fn user -> user.ap_id end)
    total = total || length(collection)

    map = %{
      "id" => "#{iri}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => total,
      "orderedItems" => if(show_items, do: items, else: [])
    }

    if offset < total do
      Map.put(map, "next", "#{iri}?page=#{page + 1}")
    else
      map
    end
  end

  defp maybe_make_image(func, key, user) do
    if image = func.(user, no_default: true) do
      %{
        key => %{
          "type" => "Image",
          "url" => image
        }
      }
    else
      %{}
    end
  end
end
