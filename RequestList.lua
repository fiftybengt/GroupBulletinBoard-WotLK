local _, GBB = GroupBulletinBoard_Loader.Main()

local tconcat = table.concat

local GetServerTime = GBB.api.GetServerTime
local RAID_CLASS_COLORS_HEX = GBB.api.RAID_CLASS_COLORS_HEX
local wipe = GBB.api.wipe

local has_wotlk = (GBB.api.content.expansion >= GBB.api.content.WOTLK)

--ScrollList / Request
-------------------------------------------------------------------------------------
local LastDungeon
local lastIsFolded
--local requestNil = { dungeon = "NIL", start = 0, last = 0, name = "" }

-- Add sort stability by adding a stable index for comparator function arguments
local DISCRIMINATOR_BASIS = 1/10000
local discriminator = 0
local discriminators = {}

local function getDiscriminator(word)
  if not discriminators[word] then
    discriminator = discriminator + 1
    discriminators[word] = discriminator * DISCRIMINATOR_BASIS
  end
  return discriminators[word]
end

local function requestSort_TOP_TOTAL( a, b )
  if GBB.dungeonSort[ a.dungeon ] < GBB.dungeonSort[ b.dungeon ] then
    return true
  elseif GBB.dungeonSort[ a.dungeon ] == GBB.dungeonSort[ b.dungeon ] then
    if a.start + getDiscriminator(a.name) > b.start + getDiscriminator(b.name) then
      return true
    end
  end
  return false
end
local function requestSort_TOP_nTOTAL( a, b )
  if not b then return false end

  if GBB.dungeonSort[ a.dungeon ] < GBB.dungeonSort[ b.dungeon ] then
    return true
  elseif GBB.dungeonSort[ a.dungeon ] == GBB.dungeonSort[ b.dungeon ] then
    if a.last + getDiscriminator(a.name) > b.last + getDiscriminator(b.name) then
      return true
    end
  end
  return false
end
local function requestSort_nTOP_TOTAL( a, b )
  if GBB.dungeonSort[ a.dungeon ] < GBB.dungeonSort[ b.dungeon ] then
    return true
  elseif GBB.dungeonSort[ a.dungeon ] == GBB.dungeonSort[ b.dungeon ] then
    if a.start + getDiscriminator(a.name) < b.start + getDiscriminator(b.name) then
      return true
    end
  end
  return false
end
local function requestSort_nTOP_nTOTAL( a, b )
  if GBB.dungeonSort[ a.dungeon ] < GBB.dungeonSort[ b.dungeon ] then
    return true
  elseif GBB.dungeonSort[ a.dungeon ] == GBB.dungeonSort[ b.dungeon ] then
    if a.last + getDiscriminator(a.name) < b.last + getDiscriminator(b.name) then
      return true
    end
  end
  return false
end

-- Render bookkeeping. Every widget call (SetText, SetPoint, SetHeight, ...)
-- forces the client to re-layout, so the list caches what it last applied to
-- each frame and only touches widgets whose content actually changed.
local renderGen = 0

local function SetTextCached( fs, text )
  if fs._gbbText ~= text then
    fs._gbbText = text
    fs:SetText( text )
    return true
  end
  return false
end

local function SetTextColorCached( fs, c )
  if fs._gbbR ~= c.r or fs._gbbG ~= c.g or fs._gbbB ~= c.b or fs._gbbA ~= c.a then
    fs._gbbR, fs._gbbG, fs._gbbB, fs._gbbA = c.r, c.g, c.b, c.a
    fs:SetTextColor( c.r, c.g, c.b, c.a )
  end
end

local function SetTopCached( f, x, yy )
  if f._gbbY ~= yy then
    f._gbbY = yy
    f:SetPoint( "TOPLEFT", GroupBulletinBoardFrame_ScrollChildFrame, "TOPLEFT", x, -yy )
  end
end

local function MarkShown( f )
  f._gbbGen = renderGen
  if not f:IsShown() then f:Show() end
end

local function CreateHeader( yy, dungeon )
  local ItemFrameName = "GBB.Dungeon_" .. dungeon
  local f = GBB.FramesEntries[ dungeon ]

  if f == nil then
    f = CreateFrame( "Frame", ItemFrameName, GroupBulletinBoardFrame_ScrollChildFrame,
      "GroupBulletinBoard_TmpHeader" )
    GBB.FramesEntries[ dungeon ] = f
    f.nameFS = _G[ ItemFrameName .. "_name" ]
    f.nameFS._gbbText = false
    f:SetPoint( "RIGHT", GroupBulletinBoardFrame_ScrollChildFrame, "RIGHT", 0, 0 )
    f.nameFS:SetPoint( "RIGHT", f, "RIGHT", 0, 0 )
    local fname, h = f.nameFS:GetFont()
    f.nameFS:SetHeight( h )
    f:SetHeight( h + 5 )
    f.nameFS:SetFontObject( GBB.DB.FontSize )
  end

  local colTXT
  if GBB.DB.ColorOnLevel then
    if GBB.dungeonLevel[ dungeon ][ 1 ] == 0 then
      colTXT = "|r"
    elseif GBB.dungeonLevel[ dungeon ][ 2 ] < GBB.UserLevel then
      colTXT = "|cFFAAAAAA"
    elseif GBB.UserLevel < GBB.dungeonLevel[ dungeon ][ 1 ] then
      colTXT = "|cffff4040"
    else
      colTXT = "|cff00ff00"
    end
  else
    colTXT = "|r"
  end

  if LastDungeon ~= "" and not (lastIsFolded and GBB.FoldedDungeons[ dungeon ]) then
    yy = yy + 10
  end

  if GBB.FoldedDungeons[ dungeon ] == true then
    colTXT = colTXT .. "[+] "
    lastIsFolded = true
  else
    lastIsFolded = false
  end

  SetTextCached( f.nameFS, colTXT .. GBB.dungeonNames[ dungeon ] ..
    " |cFFAAAAAA" .. GBB.LevelRange( dungeon ) .. "|r" )
  SetTopCached( f, 0, yy )
  MarkShown( f )

  yy = yy + f:GetHeight()
  LastDungeon = dungeon
  return yy
end

local function CreateItem( yy, i, doCompact, req, forceHight, listWidth )
  local f = GBB.FramesEntries[ i ]

  if f == nil then
    local ItemFrameName = "GBB.Item_" .. i
    f = CreateFrame( "Frame", ItemFrameName, GroupBulletinBoardFrame_ScrollChildFrame,
      "GroupBulletinBoard_TmpRequest" )
    GBB.FramesEntries[ i ] = f
    f.nameFS = _G[ ItemFrameName .. "_name" ]
    f.messageFS = _G[ ItemFrameName .. "_message" ]
    f.timeFS = _G[ ItemFrameName .. "_time" ]
    f.nameFS._gbbText = false
    f.messageFS._gbbText = false
    f.timeFS._gbbText = false
    f:SetPoint( "RIGHT", GroupBulletinBoardFrame_ScrollChildFrame, "RIGHT", 0, 0 )

    f.nameFS:SetPoint( "TOPLEFT" )
    f.timeFS:SetPoint( "TOP", f.nameFS, "TOP", 0, 0 )

    f.messageFS:SetNonSpaceWrap( false )
    f.messageFS:SetFontObject( GBB.DB.FontSize )
    f.nameFS:SetFontObject( GBB.DB.FontSize )
    f.timeFS:SetFontObject( GBB.DB.FontSize )
    if GBB.DontTrunicate then
      GBB.ClearNeeded = true
    end
    GBB.Tool.EnableHyperlink( f )
  end

  local nameFS, messageFS, timeFS = f.nameFS, f.messageFS, f.timeFS
  local chatStyle = GBB.DB.ChatStyle

  -- Anchors only need to be redone when the display style or width changes
  local layout = (doCompact < 1 and 1 or 0) + (chatStyle and 2 or 0) + (GBB.DB.DontTrunicate and 4 or 0)
  local layoutChanged = f._gbbLayout ~= layout or f._gbbWidth ~= listWidth
  if layoutChanged then
    f._gbbLayout = layout
    f._gbbWidth = listWidth
    f._gbbNameW = nil
    f._gbbTimeW = nil

    --_G[ItemFrameName .. "_name"]:SetScale(doCompact)
    --_G[ItemFrameName .. "_time"]:SetScale(doCompact)

    if doCompact < 1 then
      messageFS:SetPoint( "TOPLEFT", nameFS, "BOTTOMLEFT", 0, 0 )
      messageFS:SetPoint( "RIGHT", timeFS, "RIGHT", 0, 0 )
    else
      messageFS:SetPoint( "TOPLEFT", nameFS, "TOPRIGHT", 10, 0 )
      messageFS:SetPoint( "RIGHT", timeFS, "LEFT", -10, 0 )
    end

    if chatStyle then
      timeFS:Hide()
      nameFS:Hide()
      nameFS:SetWidth( 1 )
      timeFS:SetPoint( "LEFT", GroupBulletinBoardFrame_ScrollChildFrame, "RIGHT", 0, 0 )
    else
      timeFS:Show()
      nameFS:Show()
    end
  end

  local textChanged = false

  if req then
    local prefix
    if GBB.DB.ColorByClass and req.class and RAID_CLASS_COLORS_HEX[ req.class ] then
      prefix = "|c" .. RAID_CLASS_COLORS_HEX[ req.class ]
    else
      prefix = "|r"
    end
    local ClassIcon = ""
    if GBB.DB.ShowClassIcon and req.class and GBB.Tool.IconClass[ req.class ] then
      if doCompact < 1 or GBB.DB.ChatStyle then
        ClassIcon = GBB.Tool.IconClass[ req.class ]
      else
        ClassIcon = GBB.Tool.IconClassBig[ req.class ]
      end
    end

    local FriendIcon = (req.IsFriend and string.format( GBB.TxtEscapePicture, GBB.FriendIcon ) or "") ..
        (req.IsGuildMember and string.format( GBB.TxtEscapePicture, GBB.GuildIcon ) or "") ..
        (req.IsPastPlayer and string.format( GBB.TxtEscapePicture, GBB.PastPlayerIcon ) or "")

    local suffix = "|r"

    if GBB.RealLevel[ req.name ] then
      suffix = " (" .. GBB.RealLevel[ req.name ] .. ")" .. suffix
    end




    local ti
    if GBB.DB.ShowTotalTime then
      ti = GBB.formatTime( time() - req.start )
    else
      ti = GBB.formatTime( time() - req.last )
    end

    local typePrefix
    if req.IsHeroic == true then
      local colorHex = GBB.Tool.RGBPercToHex( GBB.DB.HeroicDungeonColor.r, GBB.DB.HeroicDungeonColor.g,
        GBB.DB.HeroicDungeonColor.b )
      typePrefix = "|c00" .. colorHex .. "[" .. GBB.L[ "heroicAbr" ] .. "]     "
    elseif req.IsRaid == true then
      typePrefix = "|c00ffff00" .. "[" .. GBB.L[ "raidAbr" ] .. "]     "
    else
      local colorHex = GBB.Tool.RGBPercToHex( GBB.DB.NormalDungeonColor.r, GBB.DB.NormalDungeonColor.g,
        GBB.DB.NormalDungeonColor.b )
      typePrefix = "|c00" .. colorHex .. "[" .. GBB.L[ "normalAbr" ] .. "]    "
    end

    local nameChanged, messageChanged
    if chatStyle then
      nameChanged = SetTextCached( nameFS, nil )
      messageChanged = SetTextCached( messageFS, ClassIcon ..
        "[" .. prefix .. req.name .. suffix .. "]" .. FriendIcon .. ": " .. req.message )
    else
      nameChanged = SetTextCached( nameFS, ClassIcon .. prefix .. req.name .. suffix .. FriendIcon )
      messageChanged = SetTextCached( messageFS, typePrefix .. suffix .. req.message )
      SetTextCached( timeFS, ti )
    end
    textChanged = nameChanged or messageChanged

    SetTextColorCached( messageFS, GBB.DB.EntryColor )
    SetTextColorCached( timeFS, GBB.DB.TimeColor )
  else
    textChanged = SetTextCached( nameFS, "Aag " )
    textChanged = SetTextCached( messageFS, "Aag " ) or textChanged
    SetTextCached( timeFS, "Aag " )
  end

  if not chatStyle then
    if textChanged or layoutChanged or not f._gbbNameStrW then
      f._gbbNameStrW = nameFS:GetStringWidth() + 10
    end
    if f._gbbNameStrW > GBB.DB.widthNames then
      GBB.DB.widthNames = f._gbbNameStrW
    end
    if f._gbbNameW ~= GBB.DB.widthNames then
      f._gbbNameW = GBB.DB.widthNames
      nameFS:SetWidth( GBB.DB.widthNames )
      textChanged = true
    end

    local w = timeFS:GetStringWidth() + 10
    if w > GBB.DB.widthTimes then
      GBB.DB.widthTimes = w
    end
    if f._gbbTimeW ~= GBB.DB.widthTimes then
      f._gbbTimeW = GBB.DB.widthTimes
      timeFS:SetPoint( "LEFT", GroupBulletinBoardFrame_ScrollChildFrame, "RIGHT", -GBB.DB.widthTimes, 0 )
      textChanged = true
    end
  end

  local h
  if not GBB.DB.DontTrunicate and forceHight then
    -- Fixed row height, no need to measure the text
    h = forceHight
  elseif textChanged or layoutChanged or not f._gbbMeasuredH then
    f:SetHeight( 999 )
    messageFS:SetHeight( 999 )
    f._gbbH = nil
    if chatStyle then
      h = messageFS:GetStringHeight()
    else
      if doCompact < 1 then
        h = nameFS:GetStringHeight() + messageFS:GetStringHeight()
      elseif GBB.DB.DontTrunicate then
        h = messageFS:GetStringHeight()
      else
        h = nameFS:GetStringHeight()
      end
    end
    f._gbbMeasuredH = h
  else
    h = f._gbbMeasuredH
  end

  SetTopCached( f, 10, yy )
  if f._gbbH ~= h then
    f._gbbH = h
    messageFS:SetHeight( h + 10 )
    f:SetHeight( h )
  end

  f.req = req
  if req then
    MarkShown( f )
  elseif f:IsShown() then
    f:Hide()
  end

  return h
end

local function WhoRequest( name )
  --DEFAULT_CHAT_FRAME:AddMessage(GBB.MSGPREFIX .. string.format(GBB.L["msgStartWho"],name))
  --DEFAULT_CHAT_FRAME.editBox:SetText("/who " .. name)
  --ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox)
  GBB.Tool.RunSlashCmd( "/who " .. name )
end

local function WhisperRequest( name )
  ChatFrame_OpenChat( "/w " .. name .. " " )
end

local function InviteRequest( name )
  GBB.Tool.RunSlashCmd( "/invite " .. name )
end

local function IgnoreRequest( name )
  for ir, req in pairs( GBB.RequestList ) do
    if type( req ) == "table" and req.name == name then
      req.last = 0
      GBB.DB.IgnoreList[name] = true
      GBB.ClearNeeded = true
      break
    end
  end
end
GBB.IgnoreRequest = IgnoreRequest

function GBB.Clear()
  if GBB.ClearNeeded or GBB.ClearTimer < time() then
    -- Compact in place (also closes holes left by removed entries)
    local list = GBB.RequestList
    local now = time()
    local keepTime = GBB.DB.TimeOut * 3
    local n = 0
    GBB.ClearTimer = GBB.MAXTIME

    for i = 1, table.maxn( list ) do
      local req = list[ i ]
      list[ i ] = nil
      if type( req ) == "table" and req.last + keepTime > now then
        if req.last < GBB.ClearTimer then
          GBB.ClearTimer = req.last
        end
        n = n + 1
        list[ n ] = req
      end
    end
    GBB.ClearTimer = GBB.ClearTimer + keepTime
    GBB.ClearNeeded = false
  end
end

local ownRequestDungeons = {}
local lastCount
function GBB.UpdateList()
  GBB.Clear()

  if not GroupBulletinBoardFrame:IsVisible() then
    return
  end

  GBB.UserLevel = UnitLevel( "player" )

  if GBB.DB.OrderNewTop then
    if GBB.DB.ShowTotalTime then
      table.sort( GBB.RequestList, requestSort_TOP_TOTAL )
    else
      -- BUG: invalid order function for sorting
      table.sort( GBB.RequestList, requestSort_TOP_nTOTAL )
    end
  else
    if GBB.DB.ShowTotalTime then
      table.sort( GBB.RequestList, requestSort_nTOP_TOTAL )
    else
      table.sort( GBB.RequestList, requestSort_nTOP_nTOTAL )
    end
  end




  -- Frames not touched during this pass get hidden at the end
  renderGen = renderGen + 1

  local now = time()
  local yy = 0
  LastDungeon = ""
  local count = 0
  local doCompact = 1
  local cEntrys = 0

  local w = GroupBulletinBoardFrame:GetWidth() - 20 - 10 - 10
  if GBB.DB.CompactStyle and not GBB.DB.ChatStyle then
    doCompact = 0.85
  end

  lastIsFolded = false

  wipe( ownRequestDungeons )
  if GBB.DBChar.DontFilterOwn then
    local playername = (GBB.api.UnitFullName( "player" ))

    for i, req in ipairs( GBB.RequestList ) do
      if type( req ) == "table" and req.name == playername and req.last + GBB.DB.TimeOut * 2 > now then
        ownRequestDungeons[ req.dungeon ] = true
      end
    end
  end

  local itemHight = CreateItem( yy, 0, doCompact, nil, nil, w )

  --GroupBulletinBoardFrame_ScrollFrame.ScrollBar.scrollStep = itemHight * 2

  if #GBB.FramesEntries < 100 then
    for i = 1, 100 do
      CreateItem( yy, i, doCompact, nil, nil, w )
    end
  end

  -- Rows far outside the visible part of the scroll frame are skipped
  -- (only possible with fixed row heights, i.e. when not untruncated)
  local cull = not GBB.DB.DontTrunicate
  local viewH = GroupBulletinBoardFrame_ScrollFrame:GetHeight()
  local viewTop = GroupBulletinBoardFrame_ScrollFrame:GetVerticalScroll() - viewH
  local viewBottom = viewTop + viewH * 3

  for i, req in ipairs( GBB.RequestList ) do
    if type( req ) == "table" then
      if (ownRequestDungeons[ req.dungeon ] == true or GBB.FilterDungeon( req.dungeon, req.IsHeroic, req.IsRaid )) and req.last + GBB.DB.TimeOut > now then
        count = count + 1

        --header
        if LastDungeon ~= req.dungeon then
          local hi
          if GBB.DB.EnableShowOnly then
            hi = GBB.dungeonSort[ LastDungeon ] or 0
          else
            hi = GBB.dungeonSort[ req.dungeon ] - 1
          end
          while hi < GBB.dungeonSort[ req.dungeon ] do
            if LastDungeon ~= "" and GBB.FoldedDungeons[ GBB.dungeonSort[ hi ] ] ~= true and GBB.DB.EnableShowOnly then
              yy = yy + itemHight * (GBB.DB.ShowOnlyNb - cEntrys)
            end
            hi = hi + 1

            if (ownRequestDungeons[ GBB.dungeonSort[ hi ] ] == true or GBB.FilterDungeon( GBB.dungeonSort[ hi ], req.IsHeroic, req.IsRaid )) then
              yy = CreateHeader( yy, GBB.dungeonSort[ hi ] )
              cEntrys = 0
            else
              cEntrys = GBB.DB.ShowOnlyNb
            end
          end
        end

        --entry
        if GBB.FoldedDungeons[ req.dungeon ] ~= true and (not GBB.DB.EnableShowOnly or cEntrys < GBB.DB.ShowOnlyNb) then
          if cull and (yy + itemHight < viewTop or yy > viewBottom) then
            yy = yy + itemHight + 3
          else
            yy = yy + CreateItem( yy, i, doCompact, req, itemHight, w ) + 3
          end
          cEntrys = cEntrys + 1
        end
      end
    end
  end

  if GBB.DB.EnableShowOnly then
    local hi = GBB.dungeonSort[ LastDungeon ] or 0
    while hi < GBB.NUM_DUNGEONS do
      if LastDungeon ~= "" and GBB.FoldedDungeons[ LastDungeon ] ~= true and GBB.DB.EnableShowOnly then
        yy = yy + itemHight * (GBB.DB.ShowOnlyNb - cEntrys)
      end
      hi = hi + 1
      if (ownRequestDungeons[ GBB.dungeonSort[ hi ] ] == true or GBB.FilterDungeon( GBB.dungeonSort[ hi ], false, false )) then
        yy = CreateHeader( yy, GBB.dungeonSort[ hi ] )
        cEntrys = 0
      else
        cEntrys = GBB.DB.ShowOnlyNb
      end
    end
  end

  for _, f in pairs( GBB.FramesEntries ) do
    if f._gbbGen ~= renderGen and f:IsShown() then
      f:Hide()
    end
  end

  yy = yy + viewH - 20

  if GroupBulletinBoardFrame_ScrollChildFrame._gbbH ~= yy then
    GroupBulletinBoardFrame_ScrollChildFrame._gbbH = yy
    GroupBulletinBoardFrame_ScrollChildFrame:SetHeight( yy )
  end
  if count ~= lastCount then
    lastCount = count
    GroupBulletinBoardFrameStatusText:SetText( string.format( GBB.L[ "msgNbRequest" ], count ) )
  end
end

local nonLfgHyperlinks = {
  [ "|Hglyph:" ] = true,
  [ "|Hspell:" ] = true,
  [ "|Henchant:" ] = true,
  [ "|Htalent:" ] = true,
  [ "|Htrade:" ] = true,
}

local function hasNonLfgHyperlinks( msg )
  for k, v in pairs( nonLfgHyperlinks ) do
    -- literal string match, not pattern
    if strfind( msg, k, 1, true ) then 
      return true
    end
  end
  return false
end

function GBB.GetDungeons( msg, name )
  if msg == nil then return {} end
  local dungeons = {}

  local isBad = false
  local isGood = false
  local isHeroic = false

  local runrequired = false
  local hasrun = false
  local runDungeon = ""

  local wordcount = 0

  if GBB.DB.TagsZhtw then
    local msgLower = msg:lower()
    for key, v in pairs( GBB.tagList ) do
      if strfind( msgLower, key ) then
        if v == GBB.TAGSEARCH then
          isGood = true
        elseif v == GBB.TAGBAD then
          break
        elseif v ~= nil then
          dungeons[ v ] = true
        end
      end
    end
    for key, v in pairs( GBB.HeroicKeywords ) do
      if strfind( msgLower, key ) then
        isHeroic = true
        break
      end
    end
    wordcount = string.len( msg )
  else
    local parts = GBB.SplitNoNb( msg )
    for _, p in pairs( parts ) do
      if p == "run" or p == "runs" then
        hasrun = true
      end

      local x = GBB.tagList[ p ]

      if GBB.HeroicKeywords[ p ] ~= nil then
        isHeroic = true
      end

      if x == nil then
        if GBB.tagList[ p .. "run" ] ~= nil then
          runDungeon = GBB.tagList[ p .. "run" ]
          runrequired = true
        end
      elseif x == GBB.TAGBAD then
        isBad = true
        break
      elseif x == GBB.TAGSEARCH then
        isGood = true
      else
        dungeons[ x ] = true
      end
    end
    wordcount = #(parts)
  end

  if runrequired and hasrun and runDungeon and isBad == false then
    dungeons[ runDungeon ] = true
  end

  local nameLevel = 0
  if name ~= nil then
    if GBB.RealLevel[ name ] then
      nameLevel = GBB.RealLevel[ name ]
    else
      for dungeon, id in pairs( dungeons ) do
        if GBB.dungeonLevel[ dungeon ][ 1 ] > 0 and nameLevel < GBB.dungeonLevel[ dungeon ][ 1 ] then
          nameLevel = GBB.dungeonLevel[ dungeon ][ 1 ]
        end
      end
    end
  end

  if dungeons[ "DEADMINES" ] and not dungeons[ "DMW" ] and not dungeons[ "DME" ] and not dungeons[ "DME" ] and name ~= nil then
    if nameLevel > 0 and nameLevel < 40 then
      dungeons[ "DM" ] = true
      dungeons[ "DM2" ] = false
    else
      dungeons[ "DM" ] = false
      dungeons[ "DM2" ] = true
    end
  end
  
  -- Irrelevant hyperlinks in lfg messages invalidate message
  if not dungeons[ "TRADE" ] and not dungeons [ "MISC" ] 
      and hasNonLfgHyperlinks( msg ) then
    isBad = true
    isGood = false
  end

  if isBad then
    --dungeons={}
  elseif isGood then
    for ip, p in pairs( GBB.dungeonSecondTags ) do
      local ok = false
      if dungeons[ ip ] == true then
        for it, t in ipairs( p ) do
          if string.sub( t, 1, 1 ) == "-" then
            if dungeons[ string.sub( t, 2 ) ] == true then
              ok = true
            end
          elseif dungeons[ t ] == true then
            ok = true
          end
        end
        if ok == false then
          for it, t in ipairs( p ) do
            if string.sub( t, 1, 1 ) ~= "-" then
              dungeons[ t ] = true
            end
          end
        end
      end
    end

    if next( dungeons ) == nil then
      dungeons[ "MISC" ] = true
    end
  elseif dungeons[ "TRADE" ] then
    isGood = true
  end

  -- remove all secondtags-dungeons
  for ip, p in pairs( GBB.dungeonSecondTags ) do
    if dungeons[ ip ] == true then
      dungeons[ ip ] = nil
    end
  end

  if GBB.DB.CombineSubDungeons then
    for ip, p in pairs( GBB.dungeonSecondTags ) do
      if ip ~= "DEATHMINES" then
        for is, subDungeon in pairs( p ) do
          if dungeons[ subDungeon ] then
            dungeons[ ip ] = true
            dungeons[ subDungeon ] = nil
          end
        end
      end
    end
  end
  

  return dungeons, isGood, isBad, wordcount, isHeroic
end

local function is_non_ascii( text )
  if not text then return false end

  for i = 1, #text do
    if text:byte( i ) > 127 then return true end
  end

  return false
end

function GBB.ParseMessage( msg, name, channel )
  if GBB.Initalized == false or name == nil or name == "" or msg == nil or msg == "" or string.len( msg ) < 4 then
    return
  end
  
  if GBB.DB.IgnoreList[name] then return end

  if GBB.DB.FilterNonAsciiMessages and is_non_ascii( msg ) then return end

  local requestTime = time()
  local doUpdate = false

  --name = GBB.Tool.Split( name, "-" )[ 1 ] -- remove GBB.ServerName

  if GBB.DB.RemoveRaidSymbols then
    msg = string.gsub( msg, "{.-}", "*" )
  else
    msg = string.gsub( msg, "{.-}", GBB.Tool.GetRaidIcon )
  end

  local updated = false

  for _, req in pairs( GBB.RequestList ) do
    if type( req ) == "table" and req.name == name and req.last + GBB.COMBINEMSGTIMER >= requestTime then
      if req.dungeon == "TRADE" then
        updated = true
        if msg ~= req.message then
          req.message = req.message .. "|n" .. msg
        end
      elseif req.dungeon ~= "DEBUG" and req.dungeon ~= "BAD" then
        if msg ~= req.message then
          msg = req.message .. "|n" .. msg
        end
        break
      end
    end
  end

  if updated == true then return end

  --flm RFD need healer and 3 dps
  local dungeonList, isGood, isBad, wordcount, isHeroic = GBB.GetDungeons( msg, name )

  if type( dungeonList ) ~= "table" then return end
  if isBad then return end

  local dungeonTXT = ""

  if GBB.DB.UseAllInLFG and isBad == false and isGood == false and string.lower( GBB.L[ "world_channel" ] ) == string.lower( channel ) then
    isGood = true
    if next( dungeonList ) == nil then
      dungeonList[ "MISC" ] = true
    end
  elseif isGood == false or isBad == true then
    dungeonList = {}
  end

  if wordcount > 1 then
    for dungeon, id in pairs( dungeonList ) do
      local index = 0
      if id == true and dungeon ~= nil then
        if dungeon ~= "TRADE" then
          for ir, req in pairs( GBB.RequestList ) do
            if type( req ) == "table" and req.name == name and req.dungeon == dungeon then
              index = ir
              break
            end
          end
        end

        local isRaid = GBB.RaidList[ dungeon ] ~= nil

        if index == 0 then
          index = #GBB.RequestList + 1
          GBB.RequestList[ index ] = {}
          GBB.RequestList[ index ].name = name
          GBB.RequestList[ index ].class = nil -- I don't like doing this, but wth...
          GBB.RequestList[ index ].start = requestTime
          GBB.RequestList[ index ].dungeon = dungeon
          GBB.RequestList[ index ].IsGuildMember = false --IsInGuild() and IsGuildMember( guid )
          GBB.RequestList[ index ].IsFriend = false      --C_FriendList.IsFriend( guid )
          GBB.RequestList[ index ].IsPastPlayer = GBB.GroupTrans[ name ] ~= nil

          if GBB.FilterDungeon( dungeon, isHeroic, isRaid ) and dungeon ~= "TRADE" and dungeon ~= "MISC" and GBB.FoldedDungeons[ dungeon ] ~= true then
            if dungeonTXT == "" then
              dungeonTXT = GBB.dungeonNames[ dungeon ]
            else
              dungeonTXT = GBB.dungeonNames[ dungeon ] .. ", " .. dungeonTXT
            end
          end
        end

        GBB.RequestList[ index ].message = msg
        GBB.RequestList[ index ].IsHeroic = isHeroic
        GBB.RequestList[ index ].IsRaid = isRaid
        GBB.RequestList[ index ].last = requestTime
        doUpdate = true
      end
    end
  end

  if dungeonTXT ~= "" and GBB.AllowInInstance() then
    if GBB.DB.NotifyChat then
      --local FriendIcon = (C_FriendList.IsFriend( guid ) and string.format( GBB.TxtEscapePicture, GBB.FriendIcon ) or "") ..
      --((IsInGuild() and IsGuildMember( guid )) and string.format( GBB.TxtEscapePicture, GBB.GuildIcon ) or "") ..
      --(GBB.GroupTrans[ name ] ~= nil and string.format( GBB.TxtEscapePicture, GBB.PastPlayerIcon ) or "")
      local FriendIcon = ""
      local linkname = "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
      if GBB.DB.OneLineNotification then
        DEFAULT_CHAT_FRAME:AddMessage( GBB.MSGPREFIX .. linkname .. FriendIcon .. ": " .. msg, GBB.DB.NotifyColor.r,
          GBB.DB.NotifyColor.g, GBB.DB.NotifyColor.b )
      else
        DEFAULT_CHAT_FRAME:AddMessage(
          GBB.MSGPREFIX .. string.format( GBB.L[ "msgNewRequest" ], linkname .. FriendIcon, dungeonTXT ),
          GBB.DB.NotifyColor.r * .8, GBB.DB.NotifyColor.g * .8, GBB.DB.NotifyColor.b * .8 )
        DEFAULT_CHAT_FRAME:AddMessage( GBB.MSGPREFIX .. msg, GBB.DB.NotifyColor.r, GBB.DB.NotifyColor.g,
          GBB.DB.NotifyColor.b )
      end
    end
    if GBB.DB.NotifySound then
      PlaySound( GBB.NotifySound )
    end
  end


  if doUpdate then
    local removed = false
    for i, req in pairs( GBB.RequestList ) do
      if type( req ) == "table" then
        if req.name == name and req.last ~= requestTime and req.dungeon ~= "TRADE" then
          GBB.RequestList[ i ] = nil
          removed = true
        end
      end
    end
    -- Close the holes right away, otherwise "#GBB.RequestList + 1" can
    -- overwrite live entries while the window is closed
    if removed then
      GBB.ClearNeeded = true
      GBB.Clear()
    end
  elseif GBB.DB.OnDebug then
    local index = #GBB.RequestList + 1
    GBB.RequestList[ index ] = {}
    GBB.RequestList[ index ].name = name
    GBB.RequestList[ index ].class = nil
    GBB.RequestList[ index ].start = requestTime
    if isBad then
      GBB.RequestList[ index ].dungeon = "BAD"
    else
      GBB.RequestList[ index ].dungeon = "DEBUG"
    end

    GBB.RequestList[ index ].message = msg
    GBB.RequestList[ index ].IsHeroic = isHeroic
    GBB.RequestList[ index ].last = requestTime
  end
end

function GBB.UnfoldAllDungeon()
  wipe( GBB.FoldedDungeons )
  GBB.UpdateList()
end

function GBB.FoldAllDungeon()
  for i = 1, GBB.NUM_DUNGEONS do
    GBB.FoldedDungeons[ GBB.dungeonSort[ i ] ] = true
  end
  GBB.UpdateList()
end

local function createMenu( DungeonID, req )
  if not GBB.PopupDynamic:Wipe( "request" .. (DungeonID or "nil") .. (req and "request" or "nil") ) then
    return
  end
  if req then
    GBB.PopupDynamic:AddItem( string.format( GBB.L[ "BtnWho" ], req.name ), false, WhoRequest, req.name )
    GBB.PopupDynamic:AddItem( string.format( GBB.L[ "BtnWhisper" ], req.name ), false, WhisperRequest, req.name )
    GBB.PopupDynamic:AddItem( string.format( GBB.L[ "BtnInvite" ], req.name ), false, InviteRequest, req.name )
    GBB.PopupDynamic:AddItem( string.format( GBB.L[ "BtnIgnore" ], req.name ), false, IgnoreRequest, req.name )
    GBB.PopupDynamic:AddItem( "", true )
  end
  if DungeonID then
    GBB.PopupDynamic:AddItem( GBB.L[ "BtnFold" ], false, GBB.FoldedDungeons, DungeonID )
    GBB.PopupDynamic:AddItem( GBB.L[ "BtnFoldAll" ], false, GBB.FoldAllDungeon )
    GBB.PopupDynamic:AddItem( GBB.L[ "BtnUnFoldAll" ], false, GBB.UnfoldAllDungeon )
    GBB.PopupDynamic:AddItem( "", true )
  end
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxShowTotalTime" ], false, GBB.DB, "ShowTotalTime" )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxOrderNewTop" ], false, GBB.DB, "OrderNewTop" )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxEnableShowOnly" ], false, GBB.DB, "EnableShowOnly" )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxChatStyle" ], false, GBB.DB, "ChatStyle" )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxCompactStyle" ], false, GBB.DB, "CompactStyle" )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxDontTrunicate" ], false, GBB.DB, "DontTrunicate" )
  GBB.PopupDynamic:AddItem( "", true )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxNotifySound" ], false, GBB.DB, "NotifySound" )
  GBB.PopupDynamic:AddItem( GBB.L[ "CboxNotifyChat" ], false, GBB.DB, "NotifyChat" )
  GBB.PopupDynamic:AddItem( "", true )
  GBB.PopupDynamic:AddItem( GBB.L[ "HeaderSettings" ], false, GBB.Options.Open, 1 )

  if has_wotlk then
    GBB.PopupDynamic:AddItem( GBB.L[ "WotlkPanelFilter" ], false, GBB.Options.Open, 2 )
  else
    GBB.PopupDynamic:AddItem( GBB.L[ "TBCPanelFilter" ], false, GBB.Options.Open, 2 )
  end

  GBB.PopupDynamic:AddItem( GBB.L[ "PanelAbout" ], false, GBB.Options.Open, 6 )
  GBB.PopupDynamic:AddItem( GBB.L[ "BtnCancel" ], false )
  GBB.PopupDynamic:Show()
end

function GBB.ClickFrame( self, button )
  if button == "LeftButton" then
  else
    createMenu()
  end
end

function GBB.ClickDungeon( self, button )
  local id = string.match( self:GetName(), "GBB.Dungeon_(.+)" )
  if id == nil or id == 0 then return end

  if button == "LeftButton" then
    if GBB.FoldedDungeons[ id ] then
      GBB.FoldedDungeons[ id ] = false
    else
      GBB.FoldedDungeons[ id ] = true
    end
    GBB.UpdateList()
  else
    createMenu( id )
  end
end

function GBB.ClickRequest( self, button )
  local id = string.match( self:GetName(), "GBB.Item_(.+)" )
  if id == nil or id == 0 then return end

  local req = self.req or GBB.RequestList[ tonumber( id ) ]
  if not req then return end
  if button == "LeftButton" then
    if IsShiftKeyDown() then
      WhoRequest( req.name )
      --SendWho( req.name )
    elseif IsControlKeyDown() then
      InviteRequest( req.name )
    else
      WhisperRequest( req.name )
    end
  else
    createMenu( nil, req )
  end
end

function GBB.RequestShowTooltip( self )
  for id in string.gmatch( self:GetName(), "GBB.Item_(.+)" ) do
    local n = _G[ self:GetName() .. "_message" ]
    local req = self.req or GBB.RequestList[ tonumber( id ) ]
    if not req then return end

    GameTooltip_SetDefaultAnchor( GameTooltip, UIParent )
    GameTooltip:SetOwner( GroupBulletinBoardFrame, "ANCHOR_TOP", 0, 0 )
    GameTooltip:ClearLines()
    
    GameTooltip:AddLine( req.message, 0.9, 0.9, 0.9, 1 )

    if GBB.DB.ChatStyle then
      GameTooltip:AddLine( string.format( GBB.L[ "msgLastTime" ], GBB.formatTime( time() - req.last ) ) ..
        "|n" .. string.format( GBB.L[ "msgTotalTime" ], GBB.formatTime( time() - req.start ) ) )
    elseif GBB.DB.ShowTotalTime then
      GameTooltip:AddLine( string.format( GBB.L[ "msgLastTime" ], GBB.formatTime( time() - req.last ) ) )
    else
      GameTooltip:AddLine( string.format( GBB.L[ "msgTotalTime" ], GBB.formatTime( time() - req.start ) ) )
    end

    if GBB.DB.EnableGroup and GBB.GroupTrans and GBB.GroupTrans[ req.name ] then
      local entry = GBB.GroupTrans[ req.name ]

      GameTooltip:AddLine( GBB.Tool.IconClass[ entry.class ] ..
        "|c" .. RAID_CLASS_COLORS_HEX[ entry.class ] ..
        entry.name )
      if entry.dungeon then
        GameTooltip:AddLine( entry.dungeon )
      end
      if entry.Note then
        GameTooltip:AddLine( entry.Note )
      end
      GameTooltip:AddLine( SecondsToTime( GetServerTime() - entry.lastSeen ) )
    end

    -- Integration with LogTracker addon (if addon is present and loaded)
    if LogTracker then
      LogTracker:AddPlayerInfoToTooltip( req.name );
    end

    GameTooltip:Show()
  end
end

function GBB.RequestHideTooltip( self )
  GameTooltip:Hide()
end
