define [
  'react'
  'react-router'
  'underscore'
  'i18n!react_files'
  'compiled/react/shared/utils/withReactElement'
  '../modules/filesEnv'
  './ColumnHeaders'
  './LoadingIndicator'
  './FolderChild'
  '../utils/getAllPages'
  '../utils/updateAPIQuerySortParams'
  'compiled/models/Folder'
  './CurrentUploads'
  './FilePreview'
  './UploadDropZone'
  '../utils/forceScreenreaderToReparse'
], (React, Router, _, I18n, withReactElement, filesEnv, ColumnHeadersComponent, LoadingIndicatorComponent, FolderChildComponent, getAllPages, updateAPIQuerySortParams, Folder, CurrentUploadsComponent, FilePreviewComponent, UploadDropZoneComponent, forceScreenreaderToReparse) ->

  ColumnHeaders = React.createFactory ColumnHeadersComponent
  LoadingIndicator = React.createFactory LoadingIndicatorComponent
  FolderChild = React.createFactory FolderChildComponent
  CurrentUploads = React.createFactory CurrentUploadsComponent
  FilePreview = React.createFactory FilePreviewComponent
  UploadDropZone = React.createFactory UploadDropZoneComponent

  LEADING_SLASH_TILL_BUT_NOT_INCLUDING_NEXT_SLASH = /^\/[^\/]*/

  ShowFolder = React.createClass
    displayName: 'ShowFolder'

    mixins: [Router.Navigation, Router.State]

    debouncedForceUpdate: _.debounce ->
      @forceUpdate() if @isMounted()
    , 0

    previousIdentifier: ""

    registerListeners: (props) ->
      return unless props.currentFolder
      props.currentFolder.folders.on('all', @debouncedForceUpdate, this)
      props.currentFolder.files.on('all', @debouncedForceUpdate, this)

    unregisterListeners: ->
      # Ensure that we clean up any dangling references when the component is destroyed.
      @props.currentFolder?.off(null, null, this)

    buildFolderPath: (splat) ->
      # We don't want the slashes to go away so we are doing some magic here
      if (splat)
        splat = splat.split('/').map((splatPiece) ->
          encodeURIComponent(splatPiece)
        ).join('/')

      '/' + (splat || '')

    getCurrentFolder: ->
      path = @buildFolderPath(@getParams().splat)

      if filesEnv.showingAllContexts
        pluralAssetString = path.split('/')[1]
        context = filesEnv.contextsDictionary[pluralAssetString] or filesEnv.contexts[0]
        {contextType, contextId} = context
        path = path.replace(LEADING_SLASH_TILL_BUT_NOT_INCLUDING_NEXT_SLASH, '')
      else
        {contextType, contextId} = filesEnv

      Folder.resolvePath(contextType, contextId, path).then (rootTillCurrentFolder) =>
        currentFolder = rootTillCurrentFolder[rootTillCurrentFolder.length - 1]
        @props.onResolvePath {currentFolder, rootTillCurrentFolder, showingSearchResults: false, pathname: window.location.pathname}

        [currentFolder.folders, currentFolder.files].forEach (collection) =>
          updateAPIQuerySortParams(collection, @getQuery())
          # TODO: use scroll position to only fetch the pages we need
          getAllPages(collection, @debouncedForceUpdate)
      , (jqXHR) =>
        try
          parsedResponse = $.parseJSON(jqXHR.responseText)
        if parsedResponse
          @setState errorMessages: parsedResponse.errors
          @redirectToCourseFiles() if @getQuery().preview?

    componentWillMount: ->
      @registerListeners(@props)
      @getCurrentFolder()

    componentWillUnmount: ->
      @unregisterListeners()

      setTimeout =>
        @props.onResolvePath({currentFolder:undefined, rootTillCurrentFolder:undefined})

    componentDidUpdate: ->
      # hooray for a11y
      @redirectToCourseFiles() if not @props.currentFolder? or @props.currentFolder?.get('locked_for_user')
      forceScreenreaderToReparse(@getDOMNode())

    componentWillReceiveProps: (newProps) ->
      @unregisterListeners()
      return unless newProps.currentFolder
      @getCurrentFolder() if window.location.pathname isnt newProps.pathname
      @registerListeners(newProps)
      [newProps.currentFolder.folders, newProps.currentFolder.files].forEach (collection) =>
        updateAPIQuerySortParams(collection, @getQuery())

    redirectToCourseFiles: ->
      isntPreviousFolder = @props.currentFolder? and (@previousIdentifier? isnt @props.currentFolder.get('id').toString())
      isPreviewForFile = window.location.pathname isnt filesEnv.baseUrl and @getQuery().preview? and @previousIdentifier isnt @getQuery().preview

      if isntPreviousFolder or isPreviewForFile
        @previousIdentifier = @props.currentFolder?.get('id').toString() or @getQuery().preview.toString()

        unless isPreviewForFile
          message = I18n.t('This folder is currently locked and unavailable to view.')
          $.flashError message
          $.screenReaderFlashMessage message

        setTimeout(=>
          @transitionTo filesEnv.baseUrl, {}, @getQuery()
        , 0)

    render: withReactElement ->
      if @state?.errorMessages
        return div {},
          @state.errorMessages.map (error) ->
            div className: 'muted', error.message
      return div({ref: 'emptyDiv'}) unless @props.currentFolder
      div role: 'grid', style: {flex: "1 1 auto"},

        div {
          ref: 'accessibilityMessage'
          className: 'ShowFolder__accessbilityMessage col-xs',
          tabIndex: 0
        },
          I18n.t("Warning: For improved accessibility in moving files, please use the Move To Dialog option found in the menu.")
        UploadDropZone(currentFolder: @props.currentFolder)
        CurrentUploads({})
        ColumnHeaders {
          ref: 'columnHeaders'
          to: (if @getParams().splat then 'folder' else 'rootFolder')
          query: @getQuery()
          params: @getParams()
          toggleAllSelected: @props.toggleAllSelected
          areAllItemsSelected: @props.areAllItemsSelected
          usageRightsRequiredForContext: @props.usageRightsRequiredForContext
          splat: @getParams().splat
        }
        if @props.currentFolder.isEmpty()
          div ref: 'folderEmpty', className: 'muted', I18n.t('this_folder_is_empty', 'This folder is empty')
        else
          @props.currentFolder.children(@getQuery()).map (child) =>
            FolderChild
              key: child.cid
              model: child
              isSelected: child in @props.selectedItems
              toggleSelected: @props.toggleItemSelected.bind(null, child)
              userCanManageFilesForContext: @props.userCanManageFilesForContext
              usageRightsRequiredForContext: @props.usageRightsRequiredForContext
              externalToolsForContext: @props.externalToolsForContext
              previewItem: @props.previewItem.bind(null, child)
              dndOptions: @props.dndOptions
              modalOptions: @props.modalOptions

        LoadingIndicator isLoading: @props.currentFolder.folders.fetchingNextPage || @props.currentFolder.files.fetchingNextPage

        # Prepare and render the FilePreview if needed.
        # As long as ?preview is present in the url.
        if @getQuery().preview?
          FilePreview
            usageRightsRequiredForContext: @props.usageRightsRequiredForContext
            currentFolder: @props.currentFolder
            params: @getParams()
            query: @getQuery()

