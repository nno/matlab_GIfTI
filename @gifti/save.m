function save(this,filename,encoding)
% Save GIfTI object in a GIfTI format file
% FORMAT save(this,filename)
% this      - GIfTI object
% filename  - name of GIfTI file to be created [Default: 'untitled.gii']
% encoding  - optional argument to specify encoding format, among
%             ASCII, Base64Binary, GZipBase64Binary, ExternalFileBinary,
%             Collada (.dae), IDTF (.idtf). [Default: 'GZipBase64Binary']
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Guillaume Flandin
% $Id: save.m 6416 2015-04-21 15:34:10Z guillaume $


% Check filename and file format
%--------------------------------------------------------------------------
ext = '.gii';
if nargin == 1
    filename = 'untitled.gii';
else
    if nargin == 3 && strcmpi(encoding,'collada')
        ext = '.dae';
    end
    if nargin == 3 && strcmpi(encoding,'idtf')
        ext = '.idtf';
    end
    [p,f,e] = fileparts(filename);
    if ~ismember(lower(e),{ext})
        e = ext;
    end
    filename = fullfile(p,[f e]);
end

% Open file for writing
%--------------------------------------------------------------------------
fid = fopen(filename,'wt');
if fid == -1
    error('Unable to write file %s: permission denied.',filename);
end

% Write file
%--------------------------------------------------------------------------
switch ext
    case '.gii'
        if nargin < 3, encoding = 'GZipBase64Binary'; end
        fid = save_gii(fid,this,encoding);
    case '.dae'
        fid = save_dae(fid,this);
    case '.idtf'
        fid = save_idtf(fid,this);
    otherwise
        error('Unknown file format.');
end

% Close file
%--------------------------------------------------------------------------
fclose(fid);

%==========================================================================
% function fid = save_gii(fid,this,encoding)
%==========================================================================
function fid = save_gii(fid,this,encoding)

% Defaults for DataArray's attributes
%--------------------------------------------------------------------------
[unused,unused,mach]   = fopen(fid);
if strncmp('ieee-be',mach,7)
    def.Endian         = 'BigEndian';
elseif strncmp('ieee-le',mach,7)
    def.Endian         = 'LittleEndian';
else
    error('[GIFTI] Unknown byte order "%s".',mach);
end
def.Encoding           = encoding;
def.Intent             = 'NIFTI_INTENT_NONE';
def.DataType           = 'NIFTI_TYPE_FLOAT32';
def.ExternalFileName   = '';
def.ExternalFileOffset = '';
def.offset             = 0;

% Edit object DataArray attributes
%--------------------------------------------------------------------------
for i=1:length(this.data)
    % Revert the dimension storage
    d = this.data{i}.attributes.Dim;
    this.data{i}.attributes = rmfield(this.data{i}.attributes,'Dim');
    this.data{i}.attributes.Dimensionality = num2str(length(d));
    for j=1:length(d)
        this.data{i}.attributes.(sprintf('Dim%d',j-1)) = num2str(d(j));
    end
    % Enforce some conventions
    this.data{i}.attributes.ArrayIndexingOrder = 'ColumnMajorOrder';
    if ~isfield(this.data{i}.attributes,'DataType') || ...
        isempty(this.data{i}.attributes.DataType)
        warning('DataType set to default: %s', def.DataType);
        this.data{i}.attributes.DataType       = def.DataType;
    end
    if ~isfield(this.data{i}.attributes,'Intent') || ...
        isempty(this.data{i}.attributes.Intent)
        warning('Intent code set to default: %s', def.Intent);
        this.data{i}.attributes.Intent         = def.Intent;
    end
    this.data{i}.attributes.Encoding           = def.Encoding;
    this.data{i}.attributes.Endian             = def.Endian;
    this.data{i}.attributes.ExternalFileName   = def.ExternalFileName;
    this.data{i}.attributes.ExternalFileOffset = def.ExternalFileOffset;
    switch this.data{i}.attributes.Encoding
        case {'ASCII', 'Base64Binary','GZipBase64Binary' }
        case 'ExternalFileBinary'
            extfilename = this.data{i}.attributes.ExternalFileName;
            if isempty(extfilename)
                [p,f] = fileparts(fopen(fid));
                extfilename = [f '.dat'];
            end
            [p,f,e] = fileparts(extfilename);
            this.data{i}.attributes.ExternalFileName   = fullfile(fileparts(fopen(fid)),[f e]);
            this.data{i}.attributes.ExternalFileOffset = num2str(def.offset);
        otherwise
            error('[GIFTI] Unknown data encoding: %s.',this.data{i}.attributes.Encoding);
    end
end


% get data is in vector form (cdata matrix requires conversion to a
% set of vectors per the GIFTI standard), without changing this.data
%--------------------------------------------------------------------------

data = get_gifti_data_vectorized(this);

% Prolog
%--------------------------------------------------------------------------
fprintf(fid,'<?xml version="1.0" encoding="UTF-8"?>\n');
fprintf(fid,'<!DOCTYPE GIFTI SYSTEM "http://www.nitrc.org/frs/download.php/115/gifti.dtd">\n');
fprintf(fid,'<GIFTI Version="1.0"  NumberOfDataArrays="%d">\n',numel(data));

o = @(x) blanks(x*3);

% MetaData
%--------------------------------------------------------------------------
fprintf(fid,'%s<MetaData',o(1));
if isempty(this.metadata)
    fprintf(fid,'/>\n');
else
    fprintf(fid,'>\n');
    for i=1:length(this.metadata)
        fprintf(fid,'%s<MD>\n',o(2));
        fprintf(fid,'%s<Name><![CDATA[%s]]></Name>\n',o(3),...
            this.metadata(i).name);
        fprintf(fid,'%s<Value><![CDATA[%s]]></Value>\n',o(3),...
            this.metadata(i).value);
        fprintf(fid,'%s</MD>\n',o(2));
    end
    fprintf(fid,'%s</MetaData>\n',o(1));
end

% LabelTable
%--------------------------------------------------------------------------
fprintf(fid,'%s<LabelTable',o(1));
if isempty(this.label)
    fprintf(fid,'/>\n');
else
    fprintf(fid,'>\n');
    for i=1:length(this.label.name)
        if ~all(isnan(this.label.rgba(i,:)))
            label_rgba = sprintf(' Red="%f" Green="%f" Blue="%f" Alpha="%f"',...
                this.label.rgba(i,:));
        else
            label_rgba = '';
        end
        fprintf(fid,'%s<Label Key="%d"%s><![CDATA[%s]]></Label>\n',o(2),...
            this.label.key(i), label_rgba, this.label.name{i});
    end
    fprintf(fid,'%s</LabelTable>\n',o(1));
end

% DataArray
%--------------------------------------------------------------------------
for i=1:length(data)
    fprintf(fid,'%s<DataArray',o(1));
    if def.offset
        data{i}.attributes.ExternalFileOffset = num2str(def.offset);
    end
    fn = sort(fieldnames(data{i}.attributes));
    oo = repmat({o(5) '\n'},length(fn),1); oo{1} = '  '; oo{end} = '';
    for j=1:length(fn)
        if strcmp(fn{j},'ExternalFileName')
            [p,f,e] = fileparts(data{i}.attributes.(fn{j}));
            attval = [f e];
        else
            attval = data{i}.attributes.(fn{j});
        end
        fprintf(fid,'%s%s="%s"%s',oo{j,1},...
                fn{j},attval,sprintf(oo{j,2}));
    end
    fprintf(fid,'>\n');
    
    % MetaData
    %----------------------------------------------------------------------
    fprintf(fid,'%s<MetaData>\n',o(2));
    for j=1:length(data{i}.metadata)
        fprintf(fid,'%s<MD>\n',o(3));
        fprintf(fid,'%s<Name><![CDATA[%s]]></Name>\n',o(4),...
            data{i}.metadata(j).name);
        fprintf(fid,'%s<Value><![CDATA[%s]]></Value>\n',o(4),...
            data{i}.metadata(j).value);
        fprintf(fid,'%s</MD>\n',o(3));
    end
    fprintf(fid,'%s</MetaData>\n',o(2));
    
    % CoordinateSystemTransformMatrix
    %----------------------------------------------------------------------
    for j=1:length(data{i}.space)
        fprintf(fid,'%s<CoordinateSystemTransformMatrix>\n',o(2));
        fprintf(fid,'%s<DataSpace><![CDATA[%s]]></DataSpace>\n',o(3),...
            data{i}.space(j).DataSpace);
        fprintf(fid,'%s<TransformedSpace><![CDATA[%s]]></TransformedSpace>\n',o(3),...
            data{i}.space(j).TransformedSpace);
        fprintf(fid,'%s<MatrixData>%s</MatrixData>\n',o(3),...
            sprintf('%f ',data{i}.space(j).MatrixData'));
        fprintf(fid,'%s</CoordinateSystemTransformMatrix>\n',o(2));
    end
    
    % Data (saved using MATLAB's ColumnMajorOrder)
    %----------------------------------------------------------------------
    fprintf(fid,'%s<Data>',o(2));
    tp = getdict;
    try
        tp = tp.(data{i}.attributes.DataType);
    catch
        error('[GIFTI] Unknown DataType.');
    end
    switch data{i}.attributes.Encoding
        case 'ASCII'
            fprintf(fid, [tp.format ' '], data{i}.data);
        case 'Base64Binary'
            fprintf(fid,base64encode(typecast(data{i}.data(:),'uint8')));
            % uses native machine format
        case 'GZipBase64Binary'
            fprintf(fid,base64encode(zstream('C',typecast(data{i}.data(:),'uint8'))));
            % uses native machine format
        case 'ExternalFileBinary'
            extfilename = data{i}.attributes.ExternalFileName;
            dat = data{i}.data;
            if isa(dat,'file_array')
                dat = subsref(dat,substruct('()',repmat({':'},1,numel(dat.dim))));
            end
            if ~def.offset
                fide = fopen(extfilename,'w'); % uses native machine format
            else
                fide = fopen(extfilename,'a'); % uses native machine format
            end
            if fide == -1
                error('Unable to write file %s: permission denied.',extfilename);
            end
            fseek(fide,0,1);
            fwrite(fide,dat,tp.class);
            def.offset = ftell(fide);
            fclose(fide);
        otherwise
            error('[GIFTI] Unknown data encoding.');
    end
    fprintf(fid,'</Data>\n');
    fprintf(fid,'%s</DataArray>\n',o(1));
end

fprintf(fid,'</GIFTI>\n');

%==========================================================================
% function data = get_gifti_data_vectorized(this)
%==========================================================================
function data = get_gifti_data_vectorized(this)
% gets the data from this.data. 
% data elements with intent 'indices' or 'cdata' are converted to a list
% of vector elements with RowMajorOrder, even if they are present as
% matrices in this.data. It also ensures (by re-ordering, if necessary),
% that data elements with intent 'indices' comes first.

n=numel(this.data);

data_cell=cell(1,n);
[data_types,i_to_vectorize]=isintent(this,{'indices','cdata'});

for i=1:n
    d=this.data{i};

    data_type_index=find(i==i_to_vectorize);
    if isempty(data_type_index)
        % no conversion needed
        data_cell{i}={d};
        continue;
    end

    switch data_types(data_type_index);
        case 1
            assert(sum(size(d)>1)<=1); % must be vector
            ncolumns=1;
            d.data=d.data(:);
            d_vec={d};
        case 2
            ncolumns=size(d.data,2);
            d_vec=cell(1,ncolumns);
            for j=1:ncolumns
                d_vec{j}=d;
                d_vec{j}.data=d.data(:,j);
            end
    end

    for j=1:ncolumns
        d_vec{j}.attributes=rmfield(d_vec{j}.attributes,'Dim1');
        d_vec{j}.attributes.Dimensionality='1';
        d_vec{j}.attributes.ArrayIndexingOrder='RowMajorOrder';
        d_vec{j}.attributes.Dim0=num2str(numel(d_vec{j}.data));
    end

    data_cell{i}=d_vec;
end

% ensure that data with indices comes first
indices_pos=i_to_vectorize(data_types==1);
indices_ordered=[indices_pos setdiff(1:n, indices_pos)];

data_cell_ordered=data_cell(indices_ordered);
data=cat(2,data_cell_ordered{:});


%==========================================================================
% function fid = save_dae(fid,this)
%==========================================================================
function fid = save_dae(fid,this)

o = @(x) blanks(x*3);

% Split the mesh into connected components
%--------------------------------------------------------------------------
s = struct(this);
try
    C = spm_mesh_label(s.faces);
    d = [];
    for i=1:numel(unique(C))
        d(i).faces    = s.faces(C==i,:);
        u             = unique(d(i).faces);
        d(i).vertices = s.vertices(u,:);
        a             = 1:max(d(i).faces(:));
        a(u)          = 1:size(d(i).vertices,1);
        %a = sparse(1,double(u),1:1:size(d(i).vertices,1));
        d(i).faces    = a(d(i).faces);
    end
    s = d;
end
    
% Prolog & root of the Collada XML file
%--------------------------------------------------------------------------
fprintf(fid,'<?xml version="1.0"?>\n');
fprintf(fid,'<COLLADA xmlns="http://www.collada.org/2008/03/COLLADASchema" version="1.5.0">\n');

% Assets
%--------------------------------------------------------------------------
fprintf(fid,'%s<asset>\n',o(1));
fprintf(fid,'%s<contributor>\n',o(2));
fprintf(fid,'%s<author_website>%s</author_website>\n',o(3),...
    'http://www.fil.ion.ucl.ac.uk/spm/');
fprintf(fid,'%s<authoring_tool>%s</authoring_tool>\n',o(3),'SPM');
fprintf(fid,'%s</contributor>\n',o(2));
fprintf(fid,'%s<created>%s</created>\n',o(2),datestr(now,'yyyy-mm-ddTHH:MM:SSZ'));
fprintf(fid,'%s<modified>%s</modified>\n',o(2),datestr(now,'yyyy-mm-ddTHH:MM:SSZ'));
fprintf(fid,'%s<unit name="millimeter" meter="0.001"/>\n',o(2));
fprintf(fid,'%s<up_axis>Z_UP</up_axis>\n',o(2));
fprintf(fid,'%s</asset>\n',o(1));

% Image, Materials, Effects
%--------------------------------------------------------------------------
%fprintf(fid,'%s<library_images/>\n',o(1));

fprintf(fid,'%s<library_materials>\n',o(1));
for i=1:numel(s)
    fprintf(fid,'%s<material id="material%d" name="material%d">\n',o(2),i,i);
    fprintf(fid,'%s<instance_effect url="#material%d-effect"/>\n',o(3),i);
    fprintf(fid,'%s</material>\n',o(2));
end
fprintf(fid,'%s</library_materials>\n',o(1));

fprintf(fid,'%s<library_effects>\n',o(1));
for i=1:numel(s)
    fprintf(fid,'%s<effect id="material%d-effect" name="material%d-effect">\n',o(2),i,i);
    fprintf(fid,'%s<profile_COMMON>\n',o(3));
    fprintf(fid,'%s<technique sid="COMMON">\n',o(4));
    fprintf(fid,'%s<lambert>\n',o(5));
    fprintf(fid,'%s<emission>\n',o(6));
    fprintf(fid,'%s<color>%f %f %f %d</color>\n',o(7),[0 0 0 1]);
    fprintf(fid,'%s</emission>\n',o(6));
    fprintf(fid,'%s<ambient>\n',o(6));
    fprintf(fid,'%s<color>%f %f %f %d</color>\n',o(7),[0 0 0 1]);
    fprintf(fid,'%s</ambient>\n',o(6));
    fprintf(fid,'%s<diffuse>\n',o(6));
    fprintf(fid,'%s<color>%f %f %f %d</color>\n',o(7),[0.5 0.5 0.5 1]);
    fprintf(fid,'%s</diffuse>\n',o(6));
    fprintf(fid,'%s<transparent>\n',o(6));
    fprintf(fid,'%s<color>%d %d %d %d</color>\n',o(7),[1 1 1 1]);
    fprintf(fid,'%s</transparent>\n',o(6));
    fprintf(fid,'%s<transparency>\n',o(6));
    fprintf(fid,'%s<float>%f</float>\n',o(7),0);
    fprintf(fid,'%s</transparency>\n',o(6));
    fprintf(fid,'%s</lambert>\n',o(5));
    fprintf(fid,'%s</technique>\n',o(4));
    fprintf(fid,'%s</profile_COMMON>\n',o(3));
    fprintf(fid,'%s</effect>\n',o(2));
end
fprintf(fid,'%s</library_effects>\n',o(1));

% Geometry
%--------------------------------------------------------------------------
fprintf(fid,'%s<library_geometries>\n',o(1));
for i=1:numel(s)
    fprintf(fid,'%s<geometry id="shape%d" name="shape%d">\n',o(2),i,i);
    fprintf(fid,'%s<mesh>\n',o(3));
    fprintf(fid,'%s<source id="shape%d-positions">\n',o(4),i);
    fprintf(fid,'%s<float_array id="shape%d-positions-array" count="%d">',o(5),i,numel(s(i).vertices));
    fprintf(fid,'%f ',repmat(s(i).vertices',1,[]));
    fprintf(fid,'</float_array>\n');
    fprintf(fid,'%s<technique_common>\n',o(5));
    fprintf(fid,'%s<accessor count="%d" offset="0" source="#shape%d-positions-array" stride="3">\n',o(6),size(s(i).vertices,1),i);
    fprintf(fid,'%s<param name="X" type="float" />\n',o(7));
    fprintf(fid,'%s<param name="Y" type="float" />\n',o(7));
    fprintf(fid,'%s<param name="Z" type="float" />\n',o(7));
    fprintf(fid,'%s</accessor>\n',o(6));
    fprintf(fid,'%s</technique_common>\n',o(5));
    fprintf(fid,'%s</source>\n',o(4));
    fprintf(fid,'%s<vertices id="shape%d-vertices">\n',o(4),i);
    fprintf(fid,'%s<input semantic="POSITION" source="#shape%d-positions"/>\n',o(5),i);
    fprintf(fid,'%s</vertices>\n',o(4));
    fprintf(fid,'%s<triangles material="material%d" count="%d">\n',o(4),i,size(s(i).faces,1));
    fprintf(fid,'%s<input semantic="VERTEX" source="#shape%d-vertices" offset="0"/>\n',o(5),i);
    fprintf(fid,'%s<p>',o(5));
    fprintf(fid,'%d ',repmat(s(i).faces',1,[])-1);
    fprintf(fid,'</p>\n');
    fprintf(fid,'%s</triangles>\n',o(4));
    fprintf(fid,'%s</mesh>\n',o(3));
    fprintf(fid,'%s</geometry>\n',o(2));
end
fprintf(fid,'%s</library_geometries>\n',o(1));

% Scene
%--------------------------------------------------------------------------
fprintf(fid,'%s<library_visual_scenes>\n',o(1));
fprintf(fid,'%s<visual_scene id="VisualSceneNode" name="SceneNode">\n',o(2));
for i=1:numel(s)
    fprintf(fid,'%s<node id="node%d">\n',o(3),i);
    fprintf(fid,'%s<instance_geometry url="#shape%d">\n',o(4),i);
    fprintf(fid,'%s<bind_material>\n',o(5));
    fprintf(fid,'%s<technique_common>\n',o(6));
    fprintf(fid,'%s<instance_material symbol="material%d" target="#material%d"/>\n',o(7),i,i);
    fprintf(fid,'%s</technique_common>\n',o(6));
    fprintf(fid,'%s</bind_material>\n',o(5));
    fprintf(fid,'%s</instance_geometry>\n',o(4));
    fprintf(fid,'%s</node>\n',o(3));
end
fprintf(fid,'%s</visual_scene>\n',o(2));
fprintf(fid,'%s</library_visual_scenes>\n',o(1));
fprintf(fid,'%s<scene>\n',o(1));
fprintf(fid,'%s<instance_visual_scene url="#VisualSceneNode" />\n',o(2));
fprintf(fid,'%s</scene>\n',o(1));

% End of XML
%--------------------------------------------------------------------------
fprintf(fid,'</COLLADA>\n');

%==========================================================================
% function fid = save_idtf(fid,this)
%==========================================================================
function fid = save_idtf(fid,this)

o = @(x) blanks(x*3);

s = struct(this);

% Compute normals
%--------------------------------------------------------------------------
if ~isfield(s,'normals')
    try
        s.normals = spm_mesh_normals(...
            struct('vertices',s.vertices,'faces',s.faces),true);
    catch
        s.normals = [];
    end
end

% Split the mesh into connected components
%--------------------------------------------------------------------------
try
    C = spm_mesh_label(s.faces);
    d = [];
    try
        if size(s.cdata,2) == 1 && (any(s.cdata>1) || any(s.cdata<0))
            mi = min(s.cdata); ma = max(s.cdata);
            s.cdata = (s.cdata-mi)/ (ma-mi);
        else
        end
    end
    for i=1:numel(unique(C))
        d(i).faces    = s.faces(C==i,:);
        u             = unique(d(i).faces);
        d(i).vertices = s.vertices(u,:);
        d(i).normals  = s.normals(u,:);
        a             = 1:max(d(i).faces(:));
        a(u)          = 1:size(d(i).vertices,1);
        %a = sparse(1,double(u),1:1:size(d(i).vertices,1));
        d(i).faces    = a(d(i).faces);
        d(i).mat      = s.mat;
        try
            d(i).cdata = s.cdata(u,:);
            if size(d(i).cdata,2) == 1
                d(i).cdata = repmat(d(i).cdata,1,3);
            end
        end
    end
    s = d;
end

% FILE_HEADER
%--------------------------------------------------------------------------
fprintf(fid,'FILE_FORMAT "IDTF"\n');
fprintf(fid,'FORMAT_VERSION 100\n\n');

% NODES
%--------------------------------------------------------------------------
for i=1:numel(s)
    fprintf(fid,'NODE "MODEL" {\n');
    fprintf(fid,'%sNODE_NAME "%s"\n',o(1),sprintf('Mesh%04d',i));
    fprintf(fid,'%sPARENT_LIST {\n',o(1));
    fprintf(fid,'%sPARENT_COUNT %d\n',o(2),1);
    fprintf(fid,'%sPARENT %d {\n',o(2),0);
    fprintf(fid,'%sPARENT_NAME "%s"\n',o(3),'<NULL>');
    fprintf(fid,'%sPARENT_TM {\n',o(3));
    I = s(i).mat; % eye(4);
    for j=1:size(I,2)
        fprintf(fid,'%s',o(4)); fprintf(fid,'%f ',I(:,j)'); fprintf(fid,'\n');
    end
    fprintf(fid,'%s}\n',o(3));
    fprintf(fid,'%s}\n',o(2));
    fprintf(fid,'%s}\n',o(1));
    fprintf(fid,'%sRESOURCE_NAME "%s"\n',o(1),sprintf('Mesh%04d',i));
    %fprintf(fid,'%sMODEL_VISIBILITY "BOTH"\n',o(1));
    fprintf(fid,'}\n\n');
end

% NODE_RESOURCES
%--------------------------------------------------------------------------
for i=1:numel(s)
    fprintf(fid,'RESOURCE_LIST "MODEL" {\n');
    fprintf(fid,'%sRESOURCE_COUNT %d\n',o(1),1);
    fprintf(fid,'%sRESOURCE %d {\n',o(1),0);
    fprintf(fid,'%sRESOURCE_NAME "%s"\n',o(2),sprintf('Mesh%04d',i));
    fprintf(fid,'%sMODEL_TYPE "MESH"\n',o(2));
    fprintf(fid,'%sMESH {\n',o(2));
    fprintf(fid,'%sFACE_COUNT %d\n',o(3),size(s(i).faces,1));
    fprintf(fid,'%sMODEL_POSITION_COUNT %d\n',o(3),size(s(i).vertices,1));
    fprintf(fid,'%sMODEL_NORMAL_COUNT %d\n',o(3),size(s(i).normals,1));
    if ~isfield(s(i),'cdata') || isempty(s(i).cdata)
        c = 0;
    else
        c = size(s(i).cdata,1);
    end
    fprintf(fid,'%sMODEL_DIFFUSE_COLOR_COUNT %d\n',o(3),c);
    fprintf(fid,'%sMODEL_SPECULAR_COLOR_COUNT %d\n',o(3),0);
    fprintf(fid,'%sMODEL_TEXTURE_COORD_COUNT %d\n',o(3),0);
    fprintf(fid,'%sMODEL_BONE_COUNT %d\n',o(3),0);
    fprintf(fid,'%sMODEL_SHADING_COUNT %d\n',o(3),1);
    fprintf(fid,'%sMODEL_SHADING_DESCRIPTION_LIST {\n',o(3));
    fprintf(fid,'%sSHADING_DESCRIPTION %d {\n',o(4),0);
    fprintf(fid,'%sTEXTURE_LAYER_COUNT %d\n',o(5),0);
    fprintf(fid,'%sSHADER_ID %d\n',o(5),0);
    fprintf(fid,'%s}\n',o(4));
    fprintf(fid,'%s}\n',o(3));
    
    fprintf(fid,'%sMESH_FACE_POSITION_LIST {\n',o(3));
    fprintf(fid,'%d %d %d\n',s(i).faces'-1);
    fprintf(fid,'%s}\n',o(3));
    
    fprintf(fid,'%sMESH_FACE_NORMAL_LIST {\n',o(3));
    fprintf(fid,'%d %d %d\n',s(i).faces'-1);
    fprintf(fid,'%s}\n',o(3));
    
    fprintf(fid,'%sMESH_FACE_SHADING_LIST {\n',o(3));
    fprintf(fid,'%d\n',zeros(size(s(i).faces,1),1));
    fprintf(fid,'%s}\n',o(3));
    
    if c
        fprintf(fid,'%sMESH_FACE_DIFFUSE_COLOR_LIST {\n',o(3));
        fprintf(fid,'%d %d %d\n',s(i).faces'-1);
        fprintf(fid,'%s}\n',o(3));
    end
    
    fprintf(fid,'%sMODEL_POSITION_LIST {\n',o(3));
    fprintf(fid,'%f %f %f\n',s(i).vertices');
    fprintf(fid,'%s}\n',o(3));
    
    fprintf(fid,'%sMODEL_NORMAL_LIST {\n',o(3));
    fprintf(fid,'%f %f %f\n',s(i).normals');
    fprintf(fid,'%s}\n',o(3));
    
    if c
        fprintf(fid,'%sMODEL_DIFFUSE_COLOR_LIST {\n',o(3));
        fprintf(fid,'%f %f %f\n',s(i).cdata');
        fprintf(fid,'%s}\n',o(3));
    end
        
    fprintf(fid,'%s}\n',o(2));
    fprintf(fid,'%s}\n',o(1));
    fprintf(fid,'}\n');
end
